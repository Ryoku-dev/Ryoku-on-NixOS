package main

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
)

// The Flathub build of Vesktop runs in a sandbox that sees only its own
// ~/.var/app folder: a theme linked into ~/.config/vesktop never reaches it,
// and a link inside its folder would point out of the sandbox. It gets a copy
// instead, and a copy is ours only while its content is a version the
// transaction knows (the prior receipt's file or the new one).
const vesktopFlatpakID = "dev.vencord.Vesktop"

// vesktopFlatpakSystemApp is where a system-wide Flathub install lives.
var vesktopFlatpakSystemApp = filepath.Join("/var/lib/flatpak/app", vesktopFlatpakID)

func vesktopFlatpakThemesRel() string {
	return filepath.Join(".var", "app", vesktopFlatpakID, "config", "vesktop", "themes")
}

// vesktopFlatpakPresent reports whether the Flathub build is installed, for the
// user or system-wide, or has already run.
func vesktopFlatpakPresent() bool {
	for _, path := range []string{
		filepath.Join(os.Getenv("HOME"), ".var", "app", vesktopFlatpakID),
		filepath.Join(dataHome(), "flatpak", "app", vesktopFlatpakID),
		vesktopFlatpakSystemApp,
	} {
		if info, err := os.Stat(path); err == nil && info.IsDir() {
			return true
		}
	}
	return false
}

func validVesktopThemeName(name string) bool {
	if !validProductPath(name) || filepath.Base(name) != name ||
		!strings.HasSuffix(name, ".theme.css") || len(name) <= len(".theme.css") {
		return false
	}
	first := name[0]
	if !(first >= 'a' && first <= 'z' || first >= 'A' && first <= 'Z' || first >= '0' && first <= '9') {
		return false
	}
	for _, char := range name {
		if char >= 'a' && char <= 'z' || char >= 'A' && char <= 'Z' ||
			char >= '0' && char <= '9' || char == '.' || char == '-' || char == '_' {
			continue
		}
		return false
	}
	return true
}

func vesktopThemeManifestFile(files []ProductFile) (ProductFile, error) {
	var theme ProductFile
	for _, file := range files {
		if !file.Install {
			continue
		}
		if theme.Destination != "" || !validVesktopThemeName(file.Destination) || file.Mode != "0644" {
			return ProductFile{}, fmt.Errorf("Vesktop theme must install one flat .theme.css file")
		}
		theme = file
	}
	if theme.Destination == "" {
		return ProductFile{}, fmt.Errorf("Vesktop theme has no installable CSS")
	}
	return theme, nil
}

func vesktopThemeReceiptFile(files []ReceiptFile) (ReceiptFile, error) {
	if len(files) != 1 || !validVesktopThemeName(files[0].Destination) || files[0].Mode != "0644" {
		return ReceiptFile{}, fmt.Errorf("Vesktop theme receipt must own one flat .theme.css file")
	}
	return files[0], nil
}

func syncVesktopTheme(journal productTransactionJournal, committed bool) error {
	oldName, oldSHA := "", ""
	if journal.PriorReceipt != nil {
		prior, err := vesktopThemeReceiptFile(journal.PriorReceipt.Files)
		if err != nil {
			return err
		}
		oldName, oldSHA = prior.Destination, prior.SHA256
	}
	newName := journal.VesktopThemeFile
	desired := oldName
	if committed {
		if journal.Operation == "remove" {
			desired = ""
		} else {
			desired = newName
		}
	}
	dst, _, err := productDestination(vesktopThemesCategory, journal.ID)
	if err != nil {
		return err
	}
	if committed && journal.Operation != "remove" {
		receipt, err := readReceipt(vesktopThemesCategory, journal.ID)
		if err != nil {
			return err
		}
		file, err := vesktopThemeReceiptFile(receipt.Files)
		if err != nil || file.Destination != newName {
			return fmt.Errorf("Vesktop theme journal does not match its receipt")
		}
	}
	if err := syncVesktopThemeLink(dst, oldName, newName, desired, committed); err != nil {
		return err
	}
	if !vesktopFlatpakPresent() {
		return nil
	}
	known := map[string][]string{}
	if oldName != "" {
		known[oldName] = append(known[oldName], oldSHA)
	}
	if newName != "" && journal.VesktopThemeSHA256 != "" {
		known[newName] = append(known[newName], journal.VesktopThemeSHA256)
	}
	return syncVesktopThemeCopy(dst, oldName, newName, desired, committed, known)
}

// syncVesktopThemeLink keeps ~/.config/vesktop/themes in step: the desired
// theme linked to the installed file, any other theme this transaction owned
// unlinked.
func syncVesktopThemeLink(dst, oldName, newName, desired string, committed bool) error {
	themesDir := filepath.Join(configHome(), "vesktop", "themes")
	if err := rejectSymlinkPath(configHome(), filepath.Join("vesktop", "themes")); err != nil {
		return err
	}
	for _, name := range []string{oldName, newName} {
		if name == "" || name == desired {
			continue
		}
		if err := removeVesktopThemeLink(filepath.Join(themesDir, name), filepath.Join(dst, name), committed); err != nil {
			return err
		}
	}
	if desired == "" {
		return nil
	}
	source, err := filepath.Abs(filepath.Join(dst, desired))
	if err != nil {
		return err
	}
	info, err := os.Lstat(source)
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return fmt.Errorf("Vesktop theme source is not a regular file: %s", source)
	}
	if err := os.MkdirAll(themesDir, 0o755); err != nil {
		return err
	}
	link := filepath.Join(themesDir, desired)
	info, err = os.Lstat(link)
	if err == nil {
		if info.Mode()&os.ModeSymlink == 0 {
			return fmt.Errorf("refusing to replace unmanaged Vesktop theme %s", link)
		}
		current, err := os.Readlink(link)
		if err != nil {
			return err
		}
		if current != source {
			return fmt.Errorf("refusing to replace unmanaged Vesktop theme %s", link)
		}
		return nil
	}
	if !os.IsNotExist(err) {
		return err
	}
	return os.Symlink(source, link)
}

func removeVesktopThemeLink(link, source string, strict bool) error {
	info, err := os.Lstat(link)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	if info.Mode()&os.ModeSymlink == 0 {
		if strict {
			return fmt.Errorf("refusing to remove unmanaged Vesktop theme %s", link)
		}
		return nil
	}
	current, err := os.Readlink(link)
	if err != nil {
		return err
	}
	expected, err := filepath.Abs(source)
	if err != nil {
		return err
	}
	if current != expected {
		if strict {
			return fmt.Errorf("refusing to remove unmanaged Vesktop theme %s", link)
		}
		return nil
	}
	return os.Remove(link)
}

// syncVesktopThemeCopy keeps the Flathub build's theme folder in step: the
// desired theme copied in, any other theme this transaction owned taken out.
func syncVesktopThemeCopy(dst, oldName, newName, desired string, committed bool, known map[string][]string) error {
	home := os.Getenv("HOME")
	if err := rejectSymlinkPath(home, vesktopFlatpakThemesRel()); err != nil {
		return err
	}
	themesDir := filepath.Join(home, vesktopFlatpakThemesRel())
	for _, name := range []string{oldName, newName} {
		if name == "" || name == desired {
			continue
		}
		if err := removeVesktopThemeCopy(filepath.Join(themesDir, name), known[name], committed); err != nil {
			return err
		}
	}
	if desired == "" {
		return nil
	}
	source := filepath.Join(dst, desired)
	info, err := os.Lstat(source)
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return fmt.Errorf("Vesktop theme source is not a regular file: %s", source)
	}
	content, err := os.ReadFile(source)
	if err != nil {
		return err
	}
	sum := sha256.Sum256(content)
	target := filepath.Join(themesDir, desired)
	current, exists, err := vesktopThemeCopySum(target)
	if err != nil {
		return err
	}
	if exists {
		if current == hex.EncodeToString(sum[:]) {
			return nil
		}
		if current == "" || !slices.Contains(known[desired], current) {
			return fmt.Errorf("refusing to replace unmanaged Vesktop theme %s", target)
		}
	}
	if err := os.MkdirAll(themesDir, 0o755); err != nil {
		return err
	}
	temporary, err := os.CreateTemp(themesDir, ".ryostore-"+desired+".*")
	if err != nil {
		return err
	}
	name := temporary.Name()
	_, err = temporary.Write(content)
	if closeErr := temporary.Close(); err == nil {
		err = closeErr
	}
	if err == nil {
		err = os.Chmod(name, 0o644)
	}
	if err == nil {
		err = os.Rename(name, target)
	}
	if err != nil {
		_ = os.Remove(name)
	}
	return err
}

func removeVesktopThemeCopy(path string, known []string, strict bool) error {
	current, exists, err := vesktopThemeCopySum(path)
	if err != nil || !exists {
		return err
	}
	if current == "" || !slices.Contains(known, current) {
		if strict {
			return fmt.Errorf("refusing to remove unmanaged Vesktop theme %s", path)
		}
		return nil
	}
	return os.Remove(path)
}

// vesktopThemeCopySum is the sha256 of the regular file at path. A path that
// exists but is not a regular file reports an empty sum: it is not a copy this
// store made.
func vesktopThemeCopySum(path string) (string, bool, error) {
	info, err := os.Lstat(path)
	if os.IsNotExist(err) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	if !info.Mode().IsRegular() {
		return "", true, nil
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", true, err
	}
	sum := sha256.Sum256(raw)
	return hex.EncodeToString(sum[:]), true, nil
}
