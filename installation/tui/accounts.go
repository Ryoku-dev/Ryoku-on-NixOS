package main

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"ryoku-i18n"
)

const (
	accountRoleAdmin    = "admin"
	accountRoleStandard = "standard"
	rootModeLocked      = "locked"
	rootModePassword    = "password"
	maxHomeLimitBytes   = uint64(1<<63 - 1)
)

var (
	accountNameRe      = regexp.MustCompile(`^[a-z_][a-z0-9_-]{0,31}$`)
	accountHashRe      = regexp.MustCompile(`^\$6\$(rounds=[0-9]+\$)?[./0-9A-Za-z]{1,16}\$[./0-9A-Za-z]{86}$`)
	accountsRuntimeDir = "/run/ryoku-installer"
	reservedAccounts   = map[string]struct{}{
		"root": {}, "nobody": {}, "nogroup": {}, "bin": {}, "daemon": {},
		"adm": {}, "mail": {}, "ftp": {}, "http": {}, "operator": {},
		"shutdown": {}, "halt": {}, "sync": {}, "games": {}, "man": {},
		"lp": {}, "news": {}, "uucp": {}, "proxy": {}, "backup": {},
		"list": {}, "irc": {}, "gnats": {}, "dbus": {}, "polkitd": {},
		"avahi": {}, "cups": {}, "sddm": {}, "greeter": {},
	}
)

type installerAccount struct {
	Name         string
	FullName     string
	Role         string
	Permissions  []string
	PasswordHash string
	LimitBytes   uint64
}

type accountsState struct {
	adminName     string
	adminFullName string
	adminPassword string
	adminConfirm  string
	adminField    int
	adminErr      string

	rootMode     string
	rootStage    int
	rootPassword string
	rootConfirm  string
	rootHash     string
	rootErr      string

	people        []installerAccount
	peopleAdding  bool
	peopleCursor  int
	personField   int
	personName    string
	personRole    string
	personPass    string
	personConfirm string
	personErr     string

	defaultHomeLimit uint64
}

func validateAccountName(name string, existing []string) error {
	if !accountNameRe.MatchString(name) {
		return fmt.Errorf("%s", i18n.T("lowercase; start with a letter or _; 32 characters at most"))
	}
	if _, reserved := reservedAccounts[name]; reserved || strings.HasPrefix(name, "systemd-") {
		return fmt.Errorf("%s", i18n.T("that name is reserved by the system"))
	}
	for _, other := range existing {
		if name == other {
			return fmt.Errorf("%s", i18n.T("that account name is already in use"))
		}
	}
	return nil
}
func (m model) validateUniqueAccountName(name string, includeAdministrator bool) error {
	if err := validateAccountName(name, nil); err != nil {
		return err
	}
	if includeAdministrator && name == m.accounts.adminName {
		return fmt.Errorf("%s", i18n.T("that account name is already in use"))
	}
	for _, person := range m.accounts.people {
		if name == person.Name {
			return fmt.Errorf("%s", i18n.T("that account name is already in use"))
		}
	}
	return nil
}

func validateAccountFullName(name string) error {
	for _, r := range name {
		if r == ':' || r < 0x20 || r == 0x7f {
			return fmt.Errorf("%s", i18n.T("full name contains an unsupported character"))
		}
	}
	return nil
}

func (m *model) loadAccountsStep(key string) {
	switch key {
	case "administrator":
		if m.accounts.adminName == "" {
			m.accounts.adminName = def(m.picks["username"], "you")
		}
		m.accounts.adminPassword, m.accounts.adminConfirm = "", ""
		m.accounts.adminField, m.accounts.adminErr = 0, ""
	case "root-account":
		if m.accounts.rootMode == "" {
			m.accounts.rootMode = rootModeLocked
		}
		m.accounts.rootStage = 0
		m.accounts.rootPassword, m.accounts.rootConfirm, m.accounts.rootErr = "", "", ""
	case "other-people":
		m.accounts.peopleAdding = false
		if len(m.accounts.people) == 0 {
			m.accounts.peopleCursor = 1
		} else {
			m.accounts.peopleCursor = clamp(m.accounts.peopleCursor, 0, len(m.accounts.people)+1)
		}
		m.resetPersonForm()
	}
}

func (m *model) resetPersonForm() {
	m.accounts.personField = 0
	m.accounts.personName = ""
	m.accounts.personRole = accountRoleStandard
	m.accounts.personPass = ""
	m.accounts.personConfirm = ""
	m.accounts.personErr = ""
}

func (m model) accountsTyping() bool {
	switch m.cur().key {
	case "administrator":
		return true
	case "root-account":
		return m.accounts.rootStage > 0
	case "other-people":
		return m.accounts.peopleAdding
	default:
		return false
	}
}

func (m *model) adminAccountKey(k string) {
	a := &m.accounts
	switch k {
	case "esc":
		m.back()
		return
	case "tab", "down":
		a.adminField = clamp(a.adminField+1, 0, 3)
		a.adminErr = ""
		return
	case "shift+tab", "up":
		a.adminField = clamp(a.adminField-1, 0, 3)
		a.adminErr = ""
		return
	case "enter":
		switch a.adminField {
		case 0:
			if err := m.validateUniqueAccountName(a.adminName, false); err != nil {
				a.adminErr = err.Error()
				return
			}
			a.adminField = 1
		case 1:
			a.adminFullName = strings.TrimSpace(a.adminFullName)
			if err := validateAccountFullName(a.adminFullName); err != nil {
				a.adminErr = err.Error()
				return
			}
			a.adminField = 2
		case 2:
			if a.adminPassword == "" {
				if m.pwHash == "" {
					a.adminErr = i18n.T("password cannot be empty")
					return
				}
				m.commitAdministrator()
				return
			}
			a.adminField = 3
		case 3:
			if !m.administratorValid() {
				return
			}
			if a.adminPassword == "" {
				a.adminField = 2
				a.adminErr = i18n.T("password cannot be empty")
				return
			}
			if a.adminConfirm != a.adminPassword {
				a.adminPassword, a.adminConfirm = "", ""
				a.adminField = 2
				a.adminErr = i18n.T("did not match, try again")
				return
			}
			hash, err := hashPassword(a.adminPassword)
			if err != nil {
				a.adminPassword, a.adminConfirm = "", ""
				a.adminField = 2
				a.adminErr = i18n.Tf("could not hash the password: %s", err)
				return
			}
			m.pwHash = hash
			m.commitAdministrator()
		}
		a.adminErr = ""
		return
	}
	a.adminErr = ""
	switch a.adminField {
	case 0:
		m.editInput(k, &a.adminName)
	case 1:
		m.editInput(k, &a.adminFullName)
	case 2:
		m.editInput(k, &a.adminPassword)
	case 3:
		m.editInput(k, &a.adminConfirm)
	}
}

func (m *model) administratorValid() bool {
	a := &m.accounts
	a.adminFullName = strings.TrimSpace(a.adminFullName)
	if err := m.validateUniqueAccountName(a.adminName, false); err != nil {
		a.adminField, a.adminErr = 0, err.Error()
		return false
	}
	if err := validateAccountFullName(a.adminFullName); err != nil {
		a.adminField, a.adminErr = 1, err.Error()
		return false
	}
	return true
}

func (m *model) commitAdministrator() {
	a := &m.accounts
	if !m.administratorValid() {
		return
	}
	m.picks["username"] = a.adminName
	m.picks["password"] = "set"
	a.adminPassword, a.adminConfirm, a.adminErr = "", "", ""
	m.advance()
}

func (m *model) rootAccountKey(k string) {
	a := &m.accounts
	if a.rootStage == 0 {
		switch k {
		case "esc":
			m.back()
		case "left", "right", "up", "down", "h", "j", "k", "l", "tab":
			if a.rootMode == rootModeLocked {
				a.rootMode = rootModePassword
			} else {
				a.rootMode = rootModeLocked
			}
		case "1":
			a.rootMode = rootModeLocked
		case "2":
			a.rootMode = rootModePassword
		case "enter":
			if a.rootMode == rootModeLocked {
				a.rootHash = ""
				m.advance()
			} else {
				a.rootStage = 1
			}
		}
		return
	}

	switch k {
	case "esc":
		a.rootStage, a.rootPassword, a.rootConfirm, a.rootErr = 0, "", "", ""
	case "enter":
		if a.rootStage == 1 {
			if a.rootPassword == "" {
				if a.rootHash != "" {
					m.advance()
					return
				}
				a.rootErr = i18n.T("password cannot be empty")
				return
			}
			a.rootStage, a.rootErr = 2, ""
			return
		}
		if a.rootConfirm != a.rootPassword {
			a.rootPassword, a.rootConfirm = "", ""
			a.rootStage = 1
			a.rootErr = i18n.T("did not match, try again")
			return
		}
		hash, err := hashPassword(a.rootPassword)
		if err != nil {
			a.rootPassword, a.rootConfirm = "", ""
			a.rootStage = 1
			a.rootErr = i18n.Tf("could not hash the password: %s", err)
			return
		}
		a.rootHash = hash
		a.rootPassword, a.rootConfirm, a.rootErr = "", "", ""
		a.rootStage = 0
		m.advance()
	default:
		a.rootErr = ""
		if a.rootStage == 1 {
			m.editInput(k, &a.rootPassword)
		} else {
			m.editInput(k, &a.rootConfirm)
		}
	}
}

func (m *model) otherPeopleKey(k string) {
	a := &m.accounts
	if !a.peopleAdding {
		max := len(a.people) + 1
		switch k {
		case "esc":
			m.back()
		case "up", "k":
			a.peopleCursor = clamp(a.peopleCursor-1, 0, max)
		case "down", "j", "tab":
			a.peopleCursor = clamp(a.peopleCursor+1, 0, max)
		case "a":
			a.peopleAdding = true
			m.resetPersonForm()
		case "d", "delete":
			if a.peopleCursor < len(a.people) {
				a.people = append(a.people[:a.peopleCursor], a.people[a.peopleCursor+1:]...)
				a.peopleCursor = clamp(a.peopleCursor, 0, len(a.people)+1)
			}
		case "enter":
			switch {
			case a.peopleCursor < len(a.people):
				return
			case a.peopleCursor == len(a.people):
				a.peopleAdding = true
				m.resetPersonForm()
			default:
				m.advance()
			}
		}
		return
	}

	switch k {
	case "esc":
		a.peopleAdding = false
		m.resetPersonForm()
		return
	case "tab", "down":
		a.personField = clamp(a.personField+1, 0, 3)
		a.personErr = ""
		return
	case "shift+tab", "up":
		a.personField = clamp(a.personField-1, 0, 3)
		a.personErr = ""
		return
	case "left", "right", "h", "l":
		if a.personField == 1 {
			if a.personRole == accountRoleAdmin {
				a.personRole = accountRoleStandard
			} else {
				a.personRole = accountRoleAdmin
			}
		}
		return
	case "enter":
		switch a.personField {
		case 0:
			if err := m.validateUniqueAccountName(a.personName, true); err != nil {
				a.personErr = err.Error()
				return
			}
			a.personField = 1
		case 1:
			a.personField = 2
		case 2:
			if a.personPass == "" {
				a.personErr = i18n.T("password cannot be empty")
				return
			}
			a.personField = 3
		case 3:
			if err := m.validateUniqueAccountName(a.personName, true); err != nil {
				a.personField, a.personErr = 0, err.Error()
				return
			}
			if a.personRole != accountRoleAdmin && a.personRole != accountRoleStandard {
				a.personField, a.personErr = 1, i18n.T("choose Administrator or Standard")
				return
			}
			if a.personPass == "" {
				a.personField, a.personErr = 2, i18n.T("password cannot be empty")
				return
			}
			if a.personConfirm != a.personPass {
				a.personPass, a.personConfirm = "", ""
				a.personField = 2
				a.personErr = i18n.T("did not match, try again")
				return
			}
			hash, err := hashPassword(a.personPass)
			if err != nil {
				a.personPass, a.personConfirm = "", ""
				a.personField = 2
				a.personErr = i18n.Tf("could not hash the password: %s", err)
				return
			}
			a.people = append(a.people, installerAccount{
				Name: a.personName, Role: a.personRole,
				Permissions: []string{"devices"}, PasswordHash: hash,
				LimitBytes: a.defaultHomeLimit,
			})
			a.peopleAdding = false
			a.peopleCursor = len(a.people)
			m.resetPersonForm()
		}
		a.personErr = ""
		return
	}

	a.personErr = ""
	switch a.personField {
	case 0:
		m.editInput(k, &a.personName)
	case 2:
		m.editInput(k, &a.personPass)
	case 3:
		m.editInput(k, &a.personConfirm)
	}
}

func accountField(label, value, placeholder string, password, selected bool) string {
	marker := "  "
	if selected {
		marker = "▸ "
	}
	entry := ""
	if selected {
		entry = inputBox(value, placeholder, password)
	} else if value == "" && placeholder != "" {
		entry = fg(cDim, placeholder)
	} else {
		shown := value
		if password {
			shown = strings.Repeat("•", len(value))
		}
		entry = fg(cText, shown)
	}
	return fg(cSub, marker+label+"  ") + entry
}

func (m model) administratorBody(inner int) string {
	a := m.accounts
	passwordHint := ""
	if m.pwHash != "" && a.adminPassword == "" {
		passwordHint = i18n.T("leave blank to keep the current password")
	}
	lines := []string{
		sty().Foreground(cSub).Width(inner).Render(i18n.T("This person can install apps and manage other accounts, like archinstall's sudo user.")),
		"",
		accountField(i18n.T("Username"), a.adminName, "you", false, a.adminField == 0),
		accountField(i18n.T("Full name (optional)"), a.adminFullName, i18n.T("Your name"), false, a.adminField == 1),
		accountField(i18n.T("Password"), a.adminPassword, passwordHint, true, a.adminField == 2),
		accountField(i18n.T("Confirm password"), a.adminConfirm, "", true, a.adminField == 3),
	}
	if a.adminPassword != "" {
		lines = append(lines, fg(cSub, i18n.T("strength: "))+strength(a.adminPassword))
	}
	if a.adminErr != "" {
		lines = append(lines, fg(cRed, "⚠ "+a.adminErr))
	}
	lines = append(lines, fg(cDim, i18n.T("tab or ↑/↓ moves · enter continues · esc back")))
	return strings.Join(lines, "\n")
}

func (m model) rootAccountBody(inner int) string {
	a := m.accounts
	if a.rootStage > 0 {
		label := i18n.T("Root password")
		value := a.rootPassword
		placeholder := ""
		if a.rootHash != "" && value == "" {
			placeholder = i18n.T("leave blank to keep the current password")
		}
		if a.rootStage == 2 {
			label, value, placeholder = i18n.T("Confirm root password"), a.rootConfirm, ""
		}
		body := accountField(label, value, placeholder, true, true)
		if a.rootStage == 1 && a.rootPassword != "" {
			body += "\n" + fg(cSub, i18n.T("strength: ")) + strength(a.rootPassword)
		}
		if a.rootErr != "" {
			body += "\n" + fg(cRed, "⚠ "+a.rootErr)
		}
		return body + "\n" + fg(cDim, i18n.T("enter to continue · esc cancel"))
	}
	choice := func(mode, title, hint string) string {
		marker := "  "
		if a.rootMode == mode {
			marker = "▸ "
			title = bold(cBrand, title)
		} else {
			title = fg(cText, title)
		}
		return marker + title + "\n" + fg(cSub, "    "+hint)
	}
	return strings.Join([]string{
		choice(rootModeLocked, i18n.T("Lock root — recommended"), i18n.T("Administrators use sudo for system changes.")),
		"",
		choice(rootModePassword, i18n.T("Set a separate root password"), i18n.T("Use a password different from the administrator's.")),
		"",
		fg(cDim, i18n.T("↑/↓ or 1/2 chooses · enter continues · esc back")),
	}, "\n")
}

func roleLabel(role string) string {
	if role == accountRoleAdmin {
		return i18n.T("Administrator")
	}
	return i18n.T("Standard")
}

func (m model) otherPeopleBody(inner int) string {
	a := m.accounts
	if a.peopleAdding {
		role := roleLabel(a.personRole)
		if a.personField == 1 {
			role = "‹ " + bold(cBrand, role) + " ›"
		}
		lines := []string{
			accountField(i18n.T("Username"), a.personName, i18n.T("account name"), false, a.personField == 0),
			fg(cSub, map[bool]string{true: "▸ ", false: "  "}[a.personField == 1]+i18n.T("Role")+"  ") + role,
			accountField(i18n.T("Password"), a.personPass, "", true, a.personField == 2),
			accountField(i18n.T("Confirm password"), a.personConfirm, "", true, a.personField == 3),
		}
		if a.personPass != "" {
			lines = append(lines, fg(cSub, i18n.T("strength: "))+strength(a.personPass))
		}
		if a.personErr != "" {
			lines = append(lines, fg(cRed, "⚠ "+a.personErr))
		}
		lines = append(lines, fg(cDim, i18n.T("tab or ↑/↓ moves · ←/→ changes role · esc cancels")))
		return strings.Join(lines, "\n")
	}

	var lines []string
	if len(a.people) == 0 {
		lines = append(lines, fg(cSub, i18n.T("No other people added.")), "")
	}
	for i, person := range a.people {
		marker := "  "
		if a.peopleCursor == i {
			marker = "▸ "
		}
		lines = append(lines, marker+fg(cText, person.Name)+fg(cSub, "  "+roleLabel(person.Role)))
	}
	addMarker, continueMarker := "  ", "  "
	if a.peopleCursor == len(a.people) {
		addMarker = "▸ "
	}
	if a.peopleCursor == len(a.people)+1 {
		continueMarker = "▸ "
	}
	lines = append(lines,
		addMarker+fg(cBrand, i18n.T("Add another person")),
		continueMarker+fg(cText, i18n.T("Continue without adding more")),
		"",
		fg(cDim, i18n.T("enter selects · a adds · d removes · esc back")),
	)
	return strings.Join(lines, "\n")
}

func accountHashValid(hash string) bool {
	return accountHashRe.MatchString(hash)
}

func (m model) accountsEnv() ([]string, error) {
	username := m.picks["username"]
	if err := validateAccountName(username, nil); err != nil {
		return nil, fmt.Errorf("administrator account: %w", err)
	}
	if !accountHashValid(m.pwHash) {
		return nil, fmt.Errorf("%s", i18n.T("administrator password is not set"))
	}
	fullName := strings.TrimSpace(m.accounts.adminFullName)
	if err := validateAccountFullName(fullName); err != nil {
		return nil, fmt.Errorf("administrator account: %w", err)
	}

	env := make([]string, 0, 5)
	if fullName != "" {
		env = append(env, "RYOKU_FULLNAME="+fullName)
	}
	mode := m.accounts.rootMode
	if mode == "" {
		mode = rootModeLocked
	}
	switch mode {
	case rootModeLocked:
		env = append(env, "RYOKU_ROOT_MODE="+rootModeLocked)
	case rootModePassword:
		if !accountHashValid(m.accounts.rootHash) {
			return nil, fmt.Errorf("%s", i18n.T("root password is not set"))
		}
		env = append(env, "RYOKU_ROOT_MODE="+rootModePassword, "RYOKU_ROOT_PASSWORD_HASH="+m.accounts.rootHash)
	default:
		return nil, fmt.Errorf("invalid root account mode %q", mode)
	}
	if m.accounts.defaultHomeLimit > 0 {
		env = append(env, "RYOKU_HOME_LIMIT_BYTES="+strconv.FormatUint(m.accounts.defaultHomeLimit, 10))
	}
	if len(m.accounts.people) == 0 {
		_ = os.Remove(filepath.Join(accountsRuntimeDir, "extra-users.tsv"))
		return env, nil
	}

	data, err := extraUsersTSV(username, m.accounts.people)
	if err != nil {
		return nil, err
	}
	path, err := writeExtraUsersTSV(data)
	if err != nil {
		return nil, fmt.Errorf("writing other accounts: %w", err)
	}
	return append(env, "RYOKU_EXTRA_USERS_FILE="+path), nil
}
func accountReviewName(username, fullName string) string {
	if strings.TrimSpace(fullName) == "" {
		return username
	}
	return fmt.Sprintf("%s (%s)", username, fullName)
}

func rootReviewLabel(mode string) string {
	if mode == rootModePassword {
		return i18n.T("separate password")
	}
	return i18n.T("locked (recommended)")
}

func extraUsersTSV(administrator string, people []installerAccount) ([]byte, error) {
	seen := map[string]struct{}{administrator: {}}
	var b strings.Builder
	for _, person := range people {
		if err := validateAccountName(person.Name, nil); err != nil {
			return nil, fmt.Errorf("account %q: %w", person.Name, err)
		}
		if _, repeated := seen[person.Name]; repeated {
			return nil, fmt.Errorf("account %q: %s", person.Name, i18n.T("that account name is already in use"))
		}
		if err := validateAccountFullName(person.FullName); err != nil {
			return nil, fmt.Errorf("account %q: %w", person.Name, err)
		}
		if person.Role != accountRoleAdmin && person.Role != accountRoleStandard {
			return nil, fmt.Errorf("account %q has invalid role %q", person.Name, person.Role)
		}
		if !accountHashValid(person.PasswordHash) {
			return nil, fmt.Errorf("account %q has no password", person.Name)
		}
		permissions := person.Permissions
		if len(permissions) == 0 {
			permissions = []string{"devices"}
		}
		permissionSeen := make(map[string]struct{}, len(permissions))
		for _, permission := range permissions {
			switch permission {
			case "admin":
				if person.Role != accountRoleAdmin {
					return nil, fmt.Errorf("standard account %q cannot request admin permission", person.Name)
				}
			case "devices", "audio", "virtualization", "containers":
			default:
				return nil, fmt.Errorf("account %q has unknown permission %q", person.Name, permission)
			}
			if _, repeated := permissionSeen[permission]; repeated {
				return nil, fmt.Errorf("account %q repeats permission %q", person.Name, permission)
			}
			permissionSeen[permission] = struct{}{}
		}
		if person.LimitBytes > maxHomeLimitBytes {
			return nil, fmt.Errorf("account %q home limit is too large", person.Name)
		}
		seen[person.Name] = struct{}{}
		fmt.Fprintf(&b, "%s\t%s\t%s\t%s\t%s\t%d\n",
			person.Name, person.FullName, person.Role, strings.Join(permissions, ","), person.PasswordHash, person.LimitBytes)
	}
	return []byte(b.String()), nil
}

func writeExtraUsersTSV(data []byte) (string, error) {
	info, err := os.Lstat(accountsRuntimeDir)
	if os.IsNotExist(err) {
		if err := os.MkdirAll(accountsRuntimeDir, 0o700); err != nil {
			return "", err
		}
	} else if err != nil {
		return "", err
	} else if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
		return "", fmt.Errorf("runtime path is not a directory")
	}
	if err := os.Chmod(accountsRuntimeDir, 0o700); err != nil {
		return "", err
	}
	tmp, err := os.CreateTemp(accountsRuntimeDir, ".extra-users-*")
	if err != nil {
		return "", err
	}
	tmpPath := tmp.Name()
	ok := false
	defer func() {
		_ = tmp.Close()
		if !ok {
			_ = os.Remove(tmpPath)
		}
	}()
	if err := tmp.Chmod(0o600); err != nil {
		return "", err
	}
	if _, err := tmp.Write(data); err != nil {
		return "", err
	}
	if err := tmp.Close(); err != nil {
		return "", err
	}
	path := filepath.Join(accountsRuntimeDir, "extra-users.tsv")
	if err := os.Rename(tmpPath, path); err != nil {
		return "", err
	}
	ok = true
	return path, nil
}
