package limineefi

import (
	"fmt"
	"os"

	"golang.org/x/sys/unix"

	i18n "ryoku-i18n"
)

const LastBootedEntryPath = "/sys/firmware/efi/efivars/LimineLastBootedEntry-513ee0d0-6e43-cb05-b272-f146a2fcb88a"

const fsImmutableFlag = 0x10

// ClearLastBootedEntry removes Limine's remembered menu selection. efivarfs
// commonly marks variables immutable, so callers must run this as root.
func ClearLastBootedEntry(path string) error {
	file, err := os.Open(path)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	flags, ioctlErr := unix.IoctlGetInt(int(file.Fd()), unix.FS_IOC_GETFLAGS)
	if ioctlErr == nil && flags&fsImmutableFlag != 0 {
		ioctlErr = unix.IoctlSetPointerInt(int(file.Fd()), unix.FS_IOC_SETFLAGS, flags&^fsImmutableFlag)
	}
	closeErr := file.Close()
	if ioctlErr != nil {
		return fmt.Errorf(i18n.T("clear Limine remembered-entry attributes: %w"), ioctlErr)
	}
	if closeErr != nil {
		return closeErr
	}
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf(i18n.T("clear Limine remembered entry: %w"), err)
	}
	return nil
}

// ClearLastBootedEntryWithSudo is the regular-user doctor path. chattr performs
// the same immutable-flag removal as ClearLastBootedEntry inside the privileged
// process before rm removes the root-owned EFI variable.
func ClearLastBootedEntryWithSudo(path string, sudo func(...string) error) error {
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return nil
	} else if err != nil {
		return err
	}
	if err := sudo("chattr", "-i", path); err != nil {
		return fmt.Errorf(i18n.T("clear Limine remembered-entry attributes: %w"), err)
	}
	if err := sudo("rm", "-f", path); err != nil {
		return fmt.Errorf(i18n.T("clear Limine remembered entry: %w"), err)
	}
	return nil
}
