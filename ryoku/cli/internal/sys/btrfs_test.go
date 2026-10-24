package sys

import (
	"reflect"
	"testing"
)

func TestFstabBtrfsRootPassesByOtherRootEntries(t *testing.T) {
	fstab := "# UUID=old / btrfs subvol=old 0 0\n" +
		"UUID=stale / ext4 defaults 1 1\n" +
		"UUID=ab / btrfs compress=zstd:1,subvolid=256 0 0\n" +
		"UUID=ab / btrfs subvol=/root,compress=zstd:1 0 0\n" +
		"UUID=cd /boot ext4 defaults 1 2\n"
	f, subvol := FstabBtrfsRoot(fstab)
	want := []string{"UUID=ab", "/", "btrfs", "subvol=/root,compress=zstd:1", "0", "0"}
	if !reflect.DeepEqual(f, want) || subvol != "root" {
		t.Fatalf("root = %q, %q; want %q, root", f, subvol, want)
	}
	if f, subvol := FstabBtrfsRoot("UUID=ab / btrfs subvolid=256 0 0\n"); f != nil || subvol != "" {
		t.Fatalf("a root without subvol= gave %q, %q", f, subvol)
	}
}
