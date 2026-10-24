package main

// gpudomain.go: the pure libvirt-domain builder for passthrough VMs, plus the
// CPU-pinning planner. Kept separate from gpuvm.go's orchestration so both are
// unit-tested as functions of their inputs, with no virsh or sysfs in the way.
//
// The generated domain is tuned for near-native passthrough: host-passthrough
// CPU with vCPU pinning (emulator/iothreads on host-reserved cores), Hyper-V
// enlightenments + hidden KVM for Windows (perf and NVIDIA hypervisor-hiding),
// virtio disk with cache=none/io=native, the dGPU (and its sibling functions)
// as vfio hostdevs, and the Looking Glass kvmfr shared-memory device. SPICE
// carries input only. The domain is named ryoku-<name> so the vfio hook binds.

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// vmSpec is everything buildDomainXML needs. GPU comes straight from the caps
// engine (slot + sibling functions); KvmfrMB is the host's kvmfr static size.
type vmSpec struct {
	Domain     string
	MemMB      int
	Pin        pinPlan
	Disk       string
	InstallISO string
	VirtioISO  string
	GPU        GPU
	KvmfrMB    int
	Windows    bool
	AMD        bool
}

// pinPlan maps guest vCPUs to host logical CPUs and reserves cores for the
// emulator/iothreads. Vcpus[i] is the host CPU that guest vCPU i pins to.
type pinPlan struct {
	Vcpus    []int
	Emulator string // host cpuset for the emulator + iothread; "" = unpinned
	Cores    int    // guest topology: physical cores
	Threads  int    // guest topology: threads per core
}

// buildPinPlan is the pure planner: given the host's physical cores (each a list
// of its thread siblings) and an optional core cap, it reserves the first
// physical core for the host/emulator and pins the rest to vCPUs, keeping thread
// siblings together. On a tiny CPU (<2 cores) it reserves nothing.
func buildPinPlan(cores [][]int, wantCores int) pinPlan {
	if len(cores) == 0 {
		return pinPlan{Vcpus: []int{0, 1}, Cores: 1, Threads: 2}
	}
	reserved := ""
	usable := cores
	if len(cores) >= 2 {
		reserved = cpusetJoin(cores[0])
		usable = cores[1:]
	}
	if wantCores > 0 && wantCores < len(usable) {
		usable = usable[:wantCores]
	}
	threads := len(usable[0])
	for _, c := range usable {
		if len(c) < threads {
			threads = len(c)
		}
	}
	if threads < 1 {
		threads = 1
	}
	var vcpus []int
	for _, c := range usable {
		for t := range threads {
			vcpus = append(vcpus, c[t])
		}
	}
	return pinPlan{Vcpus: vcpus, Emulator: reserved, Cores: len(usable), Threads: threads}
}

// detectTopology reads the host's physical cores from sysfs, grouping logical
// CPUs by their thread-sibling set. Cores are ordered by their lowest CPU id.
func detectTopology() [][]int {
	root := os.Getenv("RYOKU_SYS_ROOT")
	if root == "" {
		root = "/"
	}
	base := filepath.Join(root, "sys/devices/system/cpu")
	entries, err := os.ReadDir(base)
	if err != nil {
		return nil
	}
	seen := map[string]bool{}
	var cores [][]int
	// deterministic order: cpu0, cpu1, ... so the first physical core is reserved.
	for n := 0; ; n++ {
		name := "cpu" + strconv.Itoa(n)
		if !dirExists(filepath.Join(base, name)) {
			if n > len(entries)+8 {
				break
			}
			continue
		}
		sibsRaw := readTrim(filepath.Join(base, name, "topology/thread_siblings_list"))
		if sibsRaw == "" {
			continue
		}
		if seen[sibsRaw] {
			continue
		}
		seen[sibsRaw] = true
		if sibs := parseCPUList(sibsRaw); len(sibs) > 0 {
			cores = append(cores, sibs)
		}
	}
	return cores
}

// buildDomainXML renders the tuned libvirt domain. Pure: same spec, same bytes.
func buildDomainXML(s vmSpec) string {
	var b strings.Builder
	p := func(format string, a ...any) { fmt.Fprintf(&b, format, a...) }

	p("<domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>\n")
	p("  <name>%s</name>\n", s.Domain)
	p("  <memory unit='MiB'>%d</memory>\n", s.MemMB)
	p("  <currentMemory unit='MiB'>%d</currentMemory>\n", s.MemMB)

	p("  <vcpu placement='static'>%d</vcpu>\n", len(s.Pin.Vcpus))
	p("  <cputune>\n")
	for i, host := range s.Pin.Vcpus {
		p("    <vcpupin vcpu='%d' cpuset='%d'/>\n", i, host)
	}
	if s.Pin.Emulator != "" {
		p("    <emulatorpin cpuset='%s'/>\n", s.Pin.Emulator)
	}
	p("  </cputune>\n")

	// UEFI via firmware auto-select (portable across distros); secure boot off so
	// it always boots without key enrollment. TPM below satisfies Windows 11.
	p("  <os firmware='efi'>\n")
	p("    <type arch='x86_64' machine='q35'>hvm</type>\n")
	p("    <firmware>\n      <feature enabled='no' name='enrolled-keys'/>\n      <feature enabled='no' name='secure-boot'/>\n    </firmware>\n")
	p("    <boot dev='cdrom'/>\n    <boot dev='hd'/>\n")
	p("  </os>\n")

	p("  <features>\n    <acpi/>\n    <apic/>\n")
	if s.Windows {
		p("    <hyperv mode='custom'>\n")
		p("      <relaxed state='on'/>\n      <vapic state='on'/>\n      <spinlocks state='on' retries='8191'/>\n")
		p("      <vpindex state='on'/>\n      <runtime state='on'/>\n      <synic state='on'/>\n")
		p("      <stimer state='on'/>\n      <reset state='on'/>\n      <frequencies state='on'/>\n")
		p("      <tlbflush state='on'/>\n      <ipi state='on'/>\n      <vendor_id state='on' value='ryokuvm'/>\n")
		p("    </hyperv>\n")
		p("    <kvm>\n      <hidden state='on'/>\n    </kvm>\n")
		p("    <vmport state='off'/>\n")
	}
	p("    <ioapic driver='kvm'/>\n")
	p("  </features>\n")

	p("  <cpu mode='host-passthrough' check='none' migratable='off'>\n")
	p("    <topology sockets='1' dies='1' cores='%d' threads='%d'/>\n", s.Pin.Cores, s.Pin.Threads)
	if s.AMD && s.Pin.Threads > 1 {
		p("    <feature policy='require' name='topoext'/>\n")
	}
	p("  </cpu>\n")

	if s.Windows {
		p("  <clock offset='localtime'>\n")
		p("    <timer name='rtc' tickpolicy='catchup'/>\n    <timer name='pit' tickpolicy='delay'/>\n")
		p("    <timer name='hpet' present='no'/>\n    <timer name='hypervclock' present='yes'/>\n")
		p("  </clock>\n")
	} else {
		p("  <clock offset='utc'/>\n")
	}

	p("  <on_poweroff>destroy</on_poweroff>\n  <on_reboot>restart</on_reboot>\n  <on_crash>destroy</on_crash>\n")

	p("  <devices>\n")
	p("    <emulator>/usr/bin/qemu-system-x86_64</emulator>\n")
	// virtio system disk, tuned for passthrough throughput.
	p("    <disk type='file' device='disk'>\n")
	p("      <driver name='qemu' type='qcow2' cache='none' io='native' discard='unmap'/>\n")
	p("      <source file='%s'/>\n", s.Disk)
	p("      <target dev='vda' bus='virtio'/>\n")
	p("    </disk>\n")
	// install media + the virtio driver CD (so a Windows install sees the disk).
	p("    <disk type='file' device='cdrom'>\n      <driver name='qemu' type='raw'/>\n      <source file='%s'/>\n      <target dev='sda' bus='sata'/>\n      <readonly/>\n    </disk>\n", s.InstallISO)
	if s.VirtioISO != "" {
		p("    <disk type='file' device='cdrom'>\n      <driver name='qemu' type='raw'/>\n      <source file='%s'/>\n      <target dev='sdb' bus='sata'/>\n      <readonly/>\n    </disk>\n", s.VirtioISO)
	}
	// the dGPU and its sibling functions (audio, USB-C) as vfio hostdevs. managed
	// no: the Ryoku libvirt hook binds them to vfio-pci on start and back on stop.
	for _, fn := range hostdevFunctions(s.GPU) {
		p("    <hostdev mode='subsystem' type='pci' managed='no'>\n      <source>\n        %s\n      </source>\n    </hostdev>\n", pciSourceAddress(fn))
	}
	// SPICE for input/clipboard, with a small emulated display so the OS and
	// drivers install before the Looking Glass host app takes over the dGPU.
	p("    <graphics type='spice' autoport='yes'>\n      <listen type='address' address='127.0.0.1'/>\n      <gl enable='no'/>\n    </graphics>\n")
	p("    <video>\n      <model type='virtio' heads='1'/>\n    </video>\n")
	p("    <input type='tablet' bus='usb'/>\n    <input type='keyboard' bus='usb'/>\n")
	p("    <interface type='network'>\n      <source network='default'/>\n      <model type='virtio'/>\n    </interface>\n")
	p("    <tpm model='tpm-crb'>\n      <backend type='emulator' version='2.0'/>\n    </tpm>\n")
	// balloon off: a passthrough guest wants its RAM fixed, not reclaimable.
	p("    <memballoon model='none'/>\n")
	p("  </devices>\n")

	// Looking Glass shared memory via kvmfr, wired through the qemu namespace:
	// an ivshmem device backed by /dev/kvmfr0 at the host's static size.
	size := s.KvmfrMB * 1024 * 1024
	p("  <qemu:commandline>\n")
	p("    <qemu:arg value='-device'/>\n    <qemu:arg value='ivshmem-plain,id=shmem0,memdev=looking-glass'/>\n")
	p("    <qemu:arg value='-object'/>\n    <qemu:arg value='memory-backend-file,id=looking-glass,mem-path=/dev/kvmfr0,size=%d,share=yes'/>\n", size)
	p("  </qemu:commandline>\n")
	p("</domain>\n")
	return b.String()
}

// hostdevFunctions returns the PCI functions to pass: the caps engine's sibling
// list when it has one, else just the GPU slot.
func hostdevFunctions(g GPU) []string {
	if len(g.Functions) > 0 {
		return g.Functions
	}
	if g.Slot != "" {
		return []string{g.Slot}
	}
	return nil
}

// pciSourceAddress turns "0000:01:00.0" into a libvirt <address> element.
func pciSourceAddress(slot string) string {
	dom, bus, dev, fn := parsePCISlot(slot)
	return fmt.Sprintf("<address domain='0x%s' bus='0x%s' slot='0x%s' function='0x%s'/>", dom, bus, dev, fn)
}

// parsePCISlot splits "0000:01:00.0" into domain, bus, slot, function (hex, no
// 0x). Tolerates a missing domain ("01:00.0" -> domain 0000).
func parsePCISlot(slot string) (dom, bus, dev, fn string) {
	dom = "0000"
	rest := slot
	parts := strings.Split(slot, ":")
	if len(parts) == 3 {
		dom, rest = parts[0], parts[1]+":"+parts[2]
	}
	// rest is "bus:dev.fn"
	bd := strings.SplitN(rest, ":", 2)
	if len(bd) == 2 {
		bus = bd[0]
		rest = bd[1]
	}
	df := strings.SplitN(rest, ".", 2)
	dev = df[0]
	fn = "0"
	if len(df) == 2 {
		fn = df[1]
	}
	return dom, bus, dev, fn
}

// cpusetJoin renders a cpu-id list as a libvirt cpuset ("0,8").
func cpusetJoin(cpus []int) string {
	parts := make([]string, len(cpus))
	for i, c := range cpus {
		parts[i] = strconv.Itoa(c)
	}
	return strings.Join(parts, ",")
}

// parseCPUList expands a sysfs cpu list ("0-1", "0,8", "0-3,8-11") to ids.
func parseCPUList(s string) []int {
	var out []int
	for _, tok := range strings.Split(s, ",") {
		tok = strings.TrimSpace(tok)
		if tok == "" {
			continue
		}
		if lo, hi, ok := strings.Cut(tok, "-"); ok {
			a, e1 := strconv.Atoi(strings.TrimSpace(lo))
			z, e2 := strconv.Atoi(strings.TrimSpace(hi))
			if e1 == nil && e2 == nil {
				for v := a; v <= z; v++ {
					out = append(out, v)
				}
			}
			continue
		}
		if v, err := strconv.Atoi(tok); err == nil {
			out = append(out, v)
		}
	}
	return out
}

func dirExists(p string) bool {
	fi, err := os.Stat(p)
	return err == nil && fi.IsDir()
}
