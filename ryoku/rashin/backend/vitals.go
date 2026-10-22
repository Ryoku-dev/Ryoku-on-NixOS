package main

import (
	"bufio"
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

// Vitals is the machine snapshot served at /api/vitals and pushed on /ws/vitals.
type Vitals struct {
	Host   string     `json:"host"`
	Kernel string     `json:"kernel"`
	Uptime int64      `json:"uptime"`
	CPU    CPUVitals  `json:"cpu"`
	Mem    MemVitals  `json:"mem"`
	Disks  []Disk     `json:"disks"`
	GPU    *GPUVitals `json:"gpu,omitempty"`
}

type CPUVitals struct {
	Model   string  `json:"model"`
	Cores   int     `json:"cores"`
	Percent float64 `json:"percent"`
}

type MemVitals struct {
	Total int64 `json:"total"`
	Used  int64 `json:"used"`
}

type Disk struct {
	Mount string `json:"mount"`
	Total int64  `json:"total"`
	Used  int64  `json:"used"`
}

type GPUVitals struct {
	Name      string `json:"name"`
	Percent   int    `json:"percent"`
	VRAMUsed  int64  `json:"vramUsed"`
	VRAMTotal int64  `json:"vramTotal"`
}

// SampleVitals gathers a full snapshot. Every probe is best effort: a missing
// source yields a zero value, never an error.
func SampleVitals() Vitals {
	host, _ := os.Hostname()
	model, cores := cpuModelCores()
	total, used := memTotalUsed()
	return Vitals{
		Host:   host,
		Kernel: kernelRelease(),
		Uptime: uptimeSeconds(),
		CPU:    CPUVitals{Model: model, Cores: cores, Percent: cpuPercent()},
		Mem:    MemVitals{Total: total, Used: used},
		Disks:  diskVitals(),
		GPU:    gpuVitals(),
	}
}

// cpuState carries the previous /proc/stat aggregate so successive samples
// yield a live utilisation percentage.
var (
	cpuMu        sync.Mutex
	cpuPrevIdle  uint64
	cpuPrevTotal uint64
	cpuPrimed    bool
)

// cpuPercent computes utilisation from two /proc/stat samples. The first call
// (no prior sample) returns 0.
func cpuPercent() float64 {
	idle, total, ok := readCPUStat()
	if !ok {
		return 0
	}
	cpuMu.Lock()
	defer cpuMu.Unlock()
	if !cpuPrimed {
		cpuPrevIdle, cpuPrevTotal, cpuPrimed = idle, total, true
		return 0
	}
	dt := total - cpuPrevTotal
	di := idle - cpuPrevIdle
	cpuPrevIdle, cpuPrevTotal = idle, total
	if dt == 0 {
		return 0
	}
	pct := (1 - float64(di)/float64(dt)) * 100
	if pct < 0 {
		pct = 0
	}
	if pct > 100 {
		pct = 100
	}
	return pct
}

// readCPUStat sums the aggregate cpu line, returning idle (idle+iowait) and the
// grand total of all jiffies.
func readCPUStat() (idle, total uint64, ok bool) {
	f, err := os.Open("/proc/stat")
	if err != nil {
		return 0, 0, false
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		if !strings.HasPrefix(line, "cpu ") {
			continue
		}
		fields := strings.Fields(line)[1:]
		var sum uint64
		for i, fld := range fields {
			v, err := strconv.ParseUint(fld, 10, 64)
			if err != nil {
				continue
			}
			sum += v
			if i == 3 || i == 4 { // idle, iowait
				idle += v
			}
		}
		return idle, sum, true
	}
	return 0, 0, false
}

// cpuModelCores reads the model name and logical core count from /proc/cpuinfo.
func cpuModelCores() (string, int) {
	f, err := os.Open("/proc/cpuinfo")
	if err != nil {
		return "", 0
	}
	defer f.Close()
	model := ""
	cores := 0
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		if strings.HasPrefix(line, "processor") {
			cores++
		} else if model == "" && strings.HasPrefix(line, "model name") {
			if i := strings.IndexByte(line, ':'); i >= 0 {
				model = strings.TrimSpace(line[i+1:])
			}
		}
	}
	return model, cores
}

// memTotalUsed reads MemTotal and MemAvailable from /proc/meminfo (kB) and
// returns bytes; used = total - available.
func memTotalUsed() (total, used int64) {
	f, err := os.Open("/proc/meminfo")
	if err != nil {
		return 0, 0
	}
	defer f.Close()
	var avail int64
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) < 2 {
			continue
		}
		v, err := strconv.ParseInt(fields[1], 10, 64)
		if err != nil {
			continue
		}
		switch fields[0] {
		case "MemTotal:":
			total = v * 1024
		case "MemAvailable:":
			avail = v * 1024
		}
	}
	used = total - avail
	if used < 0 {
		used = 0
	}
	return total, used
}

// kernelRelease uses uname(2), falling back to `uname -r`.
func kernelRelease() string {
	var u syscall.Utsname
	if err := syscall.Uname(&u); err == nil {
		if r := int8ToString(u.Release[:]); r != "" {
			return r
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if out, err := exec.CommandContext(ctx, "uname", "-r").Output(); err == nil {
		return strings.TrimSpace(string(out))
	}
	return ""
}

func int8ToString(a []int8) string {
	b := make([]byte, 0, len(a))
	for _, c := range a {
		if c == 0 {
			break
		}
		b = append(b, byte(c))
	}
	return string(b)
}

func uptimeSeconds() int64 {
	b, err := os.ReadFile("/proc/uptime")
	if err != nil {
		return 0
	}
	fields := strings.Fields(string(b))
	if len(fields) == 0 {
		return 0
	}
	secs, err := strconv.ParseFloat(fields[0], 64)
	if err != nil {
		return 0
	}
	return int64(secs)
}

// diskVitals statfs()es every real block-backed mount from /proc/mounts,
// collapsing multiple mounts of one device (btrfs subvolumes report identical
// whole-filesystem numbers) to the root-most mountpoint, so the dashboard sees
// one row per physical filesystem.
func diskVitals() []Disk {
	f, err := os.Open("/proc/mounts")
	if err != nil {
		return nil
	}
	defer f.Close()
	byDev := map[string]Disk{}
	var order []string
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) < 3 {
			continue
		}
		src, mount := fields[0], fields[1]
		if !strings.HasPrefix(src, "/dev/") {
			continue
		}
		prev, dup := byDev[src]
		if dup && len(prev.Mount) <= len(mount) {
			continue // an existing mount of this device is closer to the root
		}
		var st syscall.Statfs_t
		if syscall.Statfs(mount, &st) != nil || st.Blocks == 0 {
			continue
		}
		bs := int64(st.Bsize)
		if !dup {
			order = append(order, src)
		}
		byDev[src] = Disk{
			Mount: mount,
			Total: int64(st.Blocks) * bs,
			Used:  int64(st.Blocks-st.Bfree) * bs,
		}
	}
	out := make([]Disk, 0, len(order))
	for _, src := range order {
		out = append(out, byDev[src])
	}
	return out
}

// dgpuAsleep reports whether an NVIDIA card is currently runtime-suspended.
// Cheap: one sysfs read, no process spawn, and it never touches the card itself.
func dgpuAsleep() bool {
	paths, _ := filepath.Glob("/sys/bus/pci/drivers/nvidia/*/power/runtime_status")
	for _, p := range paths {
		b, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		return strings.TrimSpace(string(b)) == "suspended"
	}
	return false
}

// gpuVitals prefers NVIDIA's own telemetry, then reads AMD's amdgpu sysfs
// counters. A suspended NVIDIA card is not probed because nvidia-smi wakes it
// out of runtime D3; an active AMD card can still be reported on a hybrid host.
func gpuVitals() *GPUVitals {
	if !dgpuAsleep() {
		if gpu := nvidiaGPUVitals(); gpu != nil {
			return gpu
		}
	}
	return amdGPUVitals("/sys/class/drm")
}

func nvidiaGPUVitals() *GPUVitals {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "nvidia-smi",
		"--query-gpu=name,utilization.gpu,memory.used,memory.total",
		"--format=csv,noheader,nounits").Output()
	if err != nil {
		return nil
	}
	line := strings.TrimSpace(firstLine(string(out)))
	if line == "" {
		return nil
	}
	parts := strings.Split(line, ",")
	if len(parts) < 4 {
		return nil
	}
	for i := range parts {
		parts[i] = strings.TrimSpace(parts[i])
	}
	pct, _ := strconv.Atoi(parts[1])
	usedMiB, _ := strconv.ParseInt(parts[2], 10, 64)
	totalMiB, _ := strconv.ParseInt(parts[3], 10, 64)
	const miB = 1024 * 1024
	return &GPUVitals{
		Name:      parts[0],
		Percent:   pct,
		VRAMUsed:  usedMiB * miB,
		VRAMTotal: totalMiB * miB,
	}
}

func amdGPUVitals(drmRoot string) *GPUVitals {
	entries, err := os.ReadDir(drmRoot)
	if err != nil {
		return nil
	}
	var best GPUVitals
	found := false
	for _, entry := range entries {
		name := entry.Name()
		if !strings.HasPrefix(name, "card") {
			continue
		}
		if _, err := strconv.Atoi(strings.TrimPrefix(name, "card")); err != nil {
			continue
		}
		device := filepath.Join(drmRoot, name, "device")
		vendor, err := os.ReadFile(filepath.Join(device, "vendor"))
		if err != nil || strings.TrimSpace(string(vendor)) != "0x1002" {
			continue
		}
		if status, err := os.ReadFile(filepath.Join(device, "power", "runtime_status")); err == nil &&
			strings.TrimSpace(string(status)) == "suspended" {
			continue
		}
		pct64, _ := readGPUCounter(filepath.Join(device, "gpu_busy_percent"))
		if pct64 < 0 {
			pct64 = 0
		} else if pct64 > 100 {
			pct64 = 100
		}
		used, _ := readGPUCounter(filepath.Join(device, "mem_info_vram_used"))
		total, _ := readGPUCounter(filepath.Join(device, "mem_info_vram_total"))
		candidate := GPUVitals{
			Name:      "AMD Radeon",
			Percent:   int(pct64),
			VRAMUsed:  used,
			VRAMTotal: total,
		}
		if !found || candidate.VRAMTotal > best.VRAMTotal {
			best = candidate
			found = true
		}
	}
	if !found {
		return nil
	}
	return &best
}

func readGPUCounter(path string) (int64, bool) {
	b, err := os.ReadFile(path)
	if err != nil {
		return 0, false
	}
	n, err := strconv.ParseInt(strings.TrimSpace(string(b)), 10, 64)
	return n, err == nil
}

// firstLine returns the first line of s without its terminator.
func firstLine(s string) string {
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	return s
}
