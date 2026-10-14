package doctor

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"ryoku-cli/internal/sys"

	i18n "ryoku-i18n"
)

// ---- reconciler: limine per-kernel boot images -------------------------------
//
// Each installed kernel boots from its own image on the ESP (a UKI under
// /boot/EFI/Linux, or an initramfs beside vmlinuz). An image left behind by
// an interrupted update, a hook that never fired, or a kernel removed under
// its entry still boots, then drops to an emergency shell after switch-root
// because its module tree is gone: the linux-cachyos "emergency mode" of #140.
// mkinitcpio only warns about a missing module, so nothing upstream catches
// it. This rebuilds a stale or missing image for every installed kernel and
// prunes the entry of a kernel the box no longer has.

type installedKernel struct {
	version string
	vmlinuz time.Time
}

// limineBootKernel is one generated "//<name>" kernel entry and the state of
// the image it boots.
type limineBootKernel struct {
	name              string
	version           string
	image             string
	imageExists       bool
	imageOlder        bool
	imageInaccessible bool
	// Why the image could not be read. A root-only /boot denies every one of
	// them on a normal `ryoku update`, which is nothing the user has to act on;
	// anything else is a real finding. Without the distinction both read as a
	// warning and every update ends on one.
	imagePermissionDenied bool
}

var (
	limineKernelImageStat  = os.Stat
	limineInstalledKernels = installedKernelVersions
	limineRebuildInitramfs = rebuildInitramfs
	liminePruneStrayImages = pruneLimineStrayImages
	limineModulesDir       = "/usr/lib/modules"
	limineReadFile         = os.ReadFile
	limineStat             = os.Stat
)

type incompleteKernel struct {
	dir     string
	pkgbase string
	reason  string
}

// installedKernelVersions maps pkgbase to module-tree version and vmlinuz
// mtime. Trees with neither pkgbase nor vmlinuz are module-only leftovers, not
// installed kernels. A tree with one but not the other remains incomplete.
// Symlinks to directories are followed; broken links, non-ENOENT inspection
// errors, or an unavailable modules directory are returned as errors.
func installedKernelVersions() (map[string]installedKernel, []incompleteKernel, error) {
	if xbpsHost() {
		return installedVoidKernelVersions(), nil, nil
	}
	out := map[string]installedKernel{}
	ents, err := os.ReadDir(limineModulesDir)
	if err != nil {
		return nil, nil, err
	}
	var incomplete []incompleteKernel
	for _, e := range ents {
		if strings.HasPrefix(e.Name(), ".") {
			continue
		}
		dir := filepath.Join(limineModulesDir, e.Name())
		if !e.IsDir() {
			if e.Type()&os.ModeSymlink == 0 {
				continue
			}
			fi, err := limineStat(dir)
			if err != nil {
				return nil, nil, err
			}
			if !fi.IsDir() {
				continue
			}
		}
		pb := filepath.Join(dir, "pkgbase")
		b, err := limineReadFile(pb)
		if err != nil {
			if !errors.Is(err, os.ErrNotExist) {
				return nil, nil, err
			}
			if _, imageErr := limineKernelImageStat(filepath.Join(dir, "vmlinuz")); imageErr != nil {
				if errors.Is(imageErr, os.ErrNotExist) {
					continue
				}
				return nil, nil, imageErr
			}
			incomplete = append(incomplete, incompleteKernel{dir: e.Name(), reason: "missing pkgbase"})
			continue
		}
		name := strings.TrimSpace(string(b))
		if name == "" || strings.ContainsAny(name, " \t\n\r/") {
			incomplete = append(incomplete, incompleteKernel{dir: e.Name(), reason: "empty pkgbase"})
			continue
		}
		fi, err := limineKernelImageStat(filepath.Join(dir, "vmlinuz"))
		if err != nil {
			if !errors.Is(err, os.ErrNotExist) {
				return nil, nil, err
			}
			incomplete = append(incomplete, incompleteKernel{dir: e.Name(), pkgbase: name, reason: "missing vmlinuz"})
			continue
		}
		out[name] = installedKernel{version: e.Name(), vmlinuz: fi.ModTime()}
	}
	return out, incomplete, nil
}

func installedVoidKernelVersions() map[string]installedKernel {
	out := map[string]installedKernel{}
	dirs, _ := filepath.Glob("/usr/lib/modules/*")
	for _, dir := range dirs {
		version := filepath.Base(dir)
		name := voidKernelEntryName(version)
		if name == "" {
			continue
		}
		fi, err := os.Stat("/boot/vmlinuz-" + version)
		if err != nil {
			continue
		}
		if previous, ok := out[name]; ok && previous.version > version {
			continue
		}
		out[name] = installedKernel{version: version, vmlinuz: fi.ModTime()}
	}
	return out
}

func voidKernelEntryName(version string) string {
	parts := strings.Split(version, ".")
	if len(parts) < 2 {
		return ""
	}
	major := leadingDigits(parts[0])
	minor := leadingDigits(parts[1])
	if major == "" || minor == "" {
		return ""
	}
	return "linux" + major + "." + minor
}

func leadingDigits(value string) string {
	at := 0
	for at < len(value) && value[at] >= '0' && value[at] <= '9' {
		at++
	}
	return value[:at]
}

// gatherLimineBootKernels reads the kernel entries directly under the OS
// directory, skipping the Snapshots submenu. esp is where boot():/ resolves.
func gatherLimineBootKernels(conf, esp string, installed map[string]installedKernel) []limineBootKernel {
	var out []limineBootKernel
	var cur *limineBootKernel
	flush := func() {
		if cur == nil {
			return
		}
		e := *cur
		if e.image != "" {
			if fi, err := limineKernelImageStat(e.image); err == nil {
				e.imageExists = true
				if k, ok := installed[e.name]; ok && !k.vmlinuz.IsZero() && fi.ModTime().Before(k.vmlinuz) {
					e.imageOlder = true
				}
			} else if !errors.Is(err, os.ErrNotExist) {
				e.imageInaccessible = true
				e.imagePermissionDenied = errors.Is(err, os.ErrPermission)
			}
		}
		out = append(out, e)
		cur = nil
	}
	inDir := false
	for _, l := range strings.Split(conf, "\n") {
		t := strings.TrimLeft(l, " \t")
		if strings.HasPrefix(t, "/") {
			switch limineDepth(t) {
			case 1:
				flush()
				inDir = true
			case 2:
				flush()
				if name := limineNodeName(t); inDir && name != "" && !strings.EqualFold(name, "Snapshots") {
					cur = &limineBootKernel{name: name}
				}
			default:
				flush()
			}
			continue
		}
		if cur == nil {
			continue
		}
		if v := strings.TrimPrefix(t, "comment: Kernel version: "); v != t {
			cur.version = strings.TrimSpace(v)
		} else if p := limineEntryImagePath(t, esp); p != "" {
			cur.image = p
		}
	}
	flush()
	return out
}

// limineEntryImagePath: the image a body line names (a UKI "path:" or an
// initramfs "module_path:"), or "".
func limineEntryImagePath(bodyLine, esp string) string {
	for _, key := range []string{"path: ", "module_path: "} {
		if v := strings.TrimPrefix(bodyLine, key); v != bodyLine {
			return resolveLimineBootPath(strings.TrimSpace(v), esp)
		}
	}
	return ""
}

// resolveLimineBootPath turns "boot():/EFI/Linux/x.efi#<hash>" into a path
// under esp, or "" when the value is not boot()-relative.
func resolveLimineBootPath(raw, esp string) string {
	rest := strings.TrimPrefix(raw, "boot():")
	if rest == raw || !strings.HasPrefix(rest, "/") {
		return ""
	}
	if i := strings.IndexByte(rest, '#'); i >= 0 {
		rest = rest[:i]
	}
	return strings.TrimRight(esp, "/") + rest
}

// planLimineKernelImages: stale is an installed kernel whose entry is missing,
// names another version, or whose image is gone or older than the kernel;
// stray is an entry for a kernel that is not installed.
func planLimineKernelImages(installed map[string]installedKernel, entries []limineBootKernel) (stale, stray []string) {
	seen := map[string]bool{}
	for _, e := range entries {
		seen[e.name] = true
		inst, ok := installed[e.name]
		if !ok {
			stray = append(stray, e.name)
			continue
		}
		if (e.version != "" && e.version != inst.version) || (e.image != "" && !e.imageExists && !e.imageInaccessible) || e.imageOlder {
			stale = append(stale, e.name)
		}
	}
	for name := range installed {
		if !seen[name] {
			stale = append(stale, name)
		}
	}
	sort.Strings(stale)
	sort.Strings(stray)
	return stale, stray
}

func incompleteEntryNames(incomplete []incompleteKernel, entries []limineBootKernel) []string {
	byName := map[string]bool{}
	for _, kernel := range incomplete {
		if kernel.pkgbase != "" {
			byName[kernel.pkgbase] = true
		}
	}
	var names []string
	for _, entry := range entries {
		if byName[entry.name] {
			names = append(names, entry.name)
			delete(byName, entry.name)
		}
	}
	sort.Strings(names)
	return names
}

func withoutKernelNames(names []string, blocked map[string]bool) []string {
	out := names[:0]
	for _, name := range names {
		if !blocked[name] {
			out = append(out, name)
		}
	}
	return out
}

// pruneLimineStrayImages removes the images of kernels the box no longer has
// and regenerates the menu so their entries drop out.
func pruneLimineStrayImages(names []string) error {
	if xbpsHost() {
		const hook = "/etc/kernel.d/post-install/50-ryoku-limine"
		if !sys.Exists(hook) {
			return fmt.Errorf(i18n.T("Void Limine kernel hook is missing"))
		}
		return sys.Sudo(hook)
	}
	want := map[string]bool{}
	for _, n := range names {
		want[n] = true
	}
	var victims []string
	efis, _ := filepath.Glob("/boot/EFI/Linux/*.efi")
	for _, path := range efis {
		base := strings.TrimSuffix(filepath.Base(path), ".efi")
		if i := strings.IndexByte(base, '_'); i >= 0 && want[base[i+1:]] {
			victims = append(victims, path)
		}
	}
	imgs, _ := filepath.Glob("/boot/initramfs-*.img")
	for _, path := range imgs {
		name := strings.TrimPrefix(strings.TrimSuffix(filepath.Base(path), ".img"), "initramfs-")
		if want[name] {
			victims = append(victims, path)
			if k := "/boot/vmlinuz-" + name; sys.Exists(k) {
				victims = append(victims, k)
			}
		}
	}
	if len(victims) > 0 {
		if err := removeRootFiles(victims...); err != nil {
			return err
		}
	}
	if sys.Has("limine-update") {
		return sys.Sudo("limine-update")
	}
	return nil
}

// reconcileLimineKernelImages: a no-op while every image matches its kernel.
func reconcileLimineKernelImages(checkOnly bool) recResult {
	if sys.NixBackend() {
		return okRes("kernel boot images are owned by the NixOS generation")
	}
	if !limineManagedBoot() {
		return unmanagedBootResult()
	}

	if !liminePkgInstalled("limine") {
		return okRes(i18n.T("not a limine-managed boot on this box"))
	}
	b, err := os.ReadFile(limineESPConf)
	if err != nil {
		return noteRes(i18n.T("no readable %s; the layout reconciler owns that"), limineESPConf)
	}
	installed, incomplete, err := limineInstalledKernels()
	if err != nil {
		return inspectionRes(errors.Is(err, os.ErrPermission),
			i18n.T("cannot inspect installed kernel metadata: %v"), err).
			withFix("sudo ryoku doctor --check")
	}
	entries := gatherLimineBootKernels(string(b), "/boot", installed)
	if len(entries) == 0 {
		return okRes(i18n.T("no tool-generated kernel entries yet; the boot tree reconciler owns that"))
	}
	blocked := incompleteEntryNames(incomplete, entries)
	if len(installed) == 0 && len(blocked) == 0 {
		return okRes(i18n.T("no installed kernels to check"))
	}
	var inaccessible []string
	permissionOnly := true
	for _, e := range entries {
		if e.imageInaccessible {
			inaccessible = append(inaccessible, e.name)
			permissionOnly = permissionOnly && e.imagePermissionDenied
		}
	}
	if len(inaccessible) > 0 {
		return inspectionRes(permissionOnly,
			i18n.T("cannot inspect kernel boot images on /boot to verify versions: %s"), strings.Join(inaccessible, ", ")).
			withFix("sudo ryoku doctor --check")
	}
	stale, stray := planLimineKernelImages(installed, entries)
	blockedSet := map[string]bool{}
	for _, name := range blocked {
		blockedSet[name] = true
	}
	stale = withoutKernelNames(stale, blockedSet)
	stray = withoutKernelNames(stray, blockedSet)
	blockedProblem := ""
	if len(blocked) > 0 {
		blockedProblem = fmt.Sprintf(i18n.T("cannot verify installed kernel metadata for %s; its module tree is incomplete"), strings.Join(blocked, ", "))
	}
	if len(stale) == 0 && len(stray) == 0 {
		if blockedProblem != "" {
			return warnRes("%s", blockedProblem).withFix("sudo ryoku doctor --check")
		}
		return okRes(i18n.T("every installed kernel has a current boot image"))
	}
	if checkOnly {
		var parts []string
		if blockedProblem != "" {
			parts = append(parts, blockedProblem)
		}
		if len(stale) > 0 {
			parts = append(parts, fmt.Sprintf(i18n.T("boot image missing, older than its kernel, or built for a version no longer installed: %s (boots into an emergency shell)"), strings.Join(stale, ", ")))
		}
		if len(stray) > 0 {
			parts = append(parts, fmt.Sprintf(i18n.T("boot entry for a kernel that is not installed: %s (a dead menu item)"), strings.Join(stray, ", ")))
		}
		detail := strings.Join(parts, "; ")
		remedy := i18n.T("ryoku doctor rebuilds the stale image(s) and prunes the stray entry")
		if blockedProblem != "" {
			return warnRes("%s", detail).withFix(remedy)
		}
		return wouldRes("%s", detail).withFix(remedy)
	}
	var done []string
	var problems []string
	if blockedProblem != "" {
		problems = append(problems, blockedProblem)
	}
	if len(stale) > 0 {
		if err := limineRebuildInitramfs(); err != nil {
			return failRes(i18n.T("kernel boot image stale for %s but the rebuild failed: %v"), strings.Join(stale, ", "), err).
				withFix(nvidiaInitramfsAdvice())
		}
		done = append(done, fmt.Sprintf(i18n.T("rebuilt the boot image for %s to match the installed kernel"), strings.Join(stale, ", ")))
	}
	if len(stray) > 0 {
		if err := liminePruneStrayImages(stray); err != nil {
			problems = append(problems, fmt.Sprintf(i18n.T("could not prune the stray entry for %s: %v"), strings.Join(stray, ", "), err))
		} else {
			done = append(done, fmt.Sprintf(i18n.T("pruned the stray boot entry for %s (kernel not installed)"), strings.Join(stray, ", ")))
		}
	}
	if len(problems) > 0 {
		return warnRes("%s", strings.Join(append(done, problems...), "; ")).
			withFix(i18n.T("check the ESP and rerun ryoku doctor"))
	}
	return fixedRes("%s", strings.Join(done, "; "))
}
