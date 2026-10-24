package main

import (
	"os/exec"
	"strings"
	"testing"
)

// The published sha512-crypt vectors from the specification the scheme comes
// from (and which glibc/libxcrypt reproduce byte for byte). These are the whole
// point of the test file: the installer computes the hash itself now, so nothing
// at install time would notice a wrong digest -- the user would only find out at
// the login prompt of a freshly installed machine.
var sha512CryptVectors = []struct{ pw, salt, want string }{
	{"Hello world!", "saltstring", "$6$saltstring$svn8UoSVapNtMuq1ukKS4tPQd8iKwSMHWjl/O817G3uBnIFNjnQJuesI68u4OTLiBFdcbYEdFCoEOfaS35inz1"},
	{"This is just a test", "toolongsaltstrin", "$6$toolongsaltstrin$lQ8jolhgVRVhY4b5pZKaysCLi0QBxGoNeKQzQ3glMhwllF7oGDZxUhx1yxdYcz/e1JSbq3y6JMxxl8audkUEm0"},
	{"a", "aaaaaaaaaaaaaaaa", "$6$aaaaaaaaaaaaaaaa$TVozGjGK2xhZv8IwnRTSyLMPFlG2m6gq5zYE7vlRSbKVD9al3JkwS9Idhn7BAkDg1S3b7f6UvU.oQPlbfElx51"},
	// A password the length of a full digest block and one past it: the
	// specification's "for each block of 64 bytes" steps are where an
	// off-by-one hides, and a 64-byte password produces the same hash as a
	// 65-byte one if the bit loop is wrong.
	{strings.Repeat("x", 64), "saltstring", "$6$saltstring$SSoAqlzjEXraQ.dDguxosFViX0Mfw4O.kEQXNqWn2FWfLIsQUWxK3xUguKKWh/yPYlb6YCK5MTl1eAQTuZtVf."},
	{strings.Repeat("x", 65), "saltstring", "$6$saltstring$6SQS3GtHC3TPYB.63O/KZyn5uBDlYfe1PvIq4EkYEmAojXOtfokMtH82Tj4wQ/EsRh3FgIyhJUtiFulxq4Yel/"},
	// An empty password still hashes. openssl passwd printed the literal
	// "<NULL>" here and exited 0, which the old shell-out would have shipped to
	// the backend as the account's hash; the wizard blocks an empty password, so
	// the guard is the hash, not the screen.
	{"", "saltstring", "$6$saltstring$kyGrqt6gmjAdtFLPrflEFifSYLCWWq1pyx95SvqinLDy2UHmj0sTF0MSLMwxPFZc3tu5kQckI8fks0zOPda3n1"},
}

func TestSha512CryptVectors(t *testing.T) {
	for _, v := range sha512CryptVectors {
		if got := sha512Crypt(v.pw, v.salt); got != v.want {
			t.Errorf("sha512Crypt(%q, %q):\n got %s\nwant %s", v.pw, v.salt, got, v.want)
		}
	}
}

// A salt longer than the scheme allows is truncated to 16 characters, the way
// every other implementation does it, so a hash stays verifiable.
func TestSha512CryptTruncatesLongSalt(t *testing.T) {
	long := sha512Crypt("Hello world!", "saltstringsaltstringsaltstring")
	short := sha512Crypt("Hello world!", "saltstringsaltst")
	if long != short {
		t.Errorf("a >16-char salt must be truncated:\n %s\n %s", long, short)
	}
}

// The shape the backend's `chpasswd -e` (backend/lib/chroot.sh) is handed.
func TestHashPasswordShape(t *testing.T) {
	h, err := hashPassword("ryoku-test-password")
	if err != nil {
		t.Fatalf("hashPassword: %v", err)
	}
	parts := strings.Split(h, "$")
	if len(parts) != 4 || parts[0] != "" || parts[1] != "6" {
		t.Fatalf("hash must be $6$salt$digest, got %q", h)
	}
	if len(parts[2]) != cryptSaltLen {
		t.Errorf("salt is %d chars, want %d: %q", len(parts[2]), cryptSaltLen, parts[2])
	}
	if len(parts[3]) != 86 {
		t.Errorf("digest is %d chars, want 86: %q", len(parts[3]), parts[3])
	}
	for _, c := range parts[2] + parts[3] {
		if !strings.ContainsRune(cryptAlphabet, c) {
			t.Errorf("%q is outside the crypt alphabet: %q", c, h)
		}
	}
	// The hash must verify against its own salt, which is what the login prompt
	// will do: recomputing from the embedded salt has to land on the same digest.
	if again := sha512Crypt("ryoku-test-password", parts[2]); again != h {
		t.Errorf("hash does not reproduce from its own salt:\n %s\n %s", h, again)
	}
	if wrong := sha512Crypt("ryoku-test-passwore", parts[2]); wrong == h {
		t.Error("a different password produced the same hash")
	}
}

// Every call salts freshly: two users typing the same password must not end up
// with the same hash.
func TestHashPasswordSaltsPerCall(t *testing.T) {
	seen := map[string]bool{}
	for range 8 {
		h, err := hashPassword("same password")
		if err != nil {
			t.Fatalf("hashPassword: %v", err)
		}
		if seen[h] {
			t.Fatalf("repeated hash for the same password: %s", h)
		}
		seen[h] = true
	}
}

// Whatever the user can type at the password step has to hash: the keyboard step
// runs first precisely so a non-us layout reaches this screen, so non-ASCII and
// shell-significant bytes are ordinary input here, not edge cases.
func TestHashPasswordAcceptsAnyInput(t *testing.T) {
	for _, pw := range []string{
		"", "a", "pässwörd£€", "日本語のパスワード", "a b\tc",
		`$6$not-a-hash`, `a:b`, `'"` + "`" + `\`, strings.Repeat("long", 200),
	} {
		h, err := hashPassword(pw)
		if err != nil {
			t.Fatalf("hashPassword(%q): %v", pw, err)
		}
		if !strings.HasPrefix(h, "$6$") || len(h) != 3+cryptSaltLen+1+86 {
			t.Errorf("hashPassword(%q) = %q, not a sha512-crypt hash", pw, h)
		}
		if strings.ContainsAny(h, ":\n") {
			// chroot.sh feeds "user:hash" lines to chpasswd; a colon or newline
			// in the hash would split the line.
			t.Errorf("hashPassword(%q) = %q contains a chpasswd delimiter", pw, h)
		}
	}
}

// Cross-check against the C library's own crypt(3) when a Perl is around to
// reach it (the ISO gate's runner has one). The vectors above are the real
// contract; this catches a divergence from the platform implementation that
// happens to agree with the vectors.
func TestSha512CryptMatchesLibcCrypt(t *testing.T) {
	perl, err := exec.LookPath("perl")
	if err != nil {
		t.Skip("no perl to reach crypt(3)")
	}
	for _, pw := range []string{"Hello world!", "ryoku", "pässwörd", strings.Repeat("z", 100), ""} {
		salt, err := cryptSalt()
		if err != nil {
			t.Fatalf("cryptSalt: %v", err)
		}
		out, err := exec.Command(perl, "-e", "print crypt($ARGV[0], $ARGV[1])", pw, "$6$"+salt).Output()
		if err != nil {
			t.Fatalf("perl crypt: %v", err)
		}
		want := strings.TrimSpace(string(out))
		if !strings.HasPrefix(want, "$6$") {
			t.Skipf("this crypt(3) does not do sha512-crypt: %q", want)
		}
		if got := sha512Crypt(pw, salt); got != want {
			t.Errorf("pw %q salt %q:\n go   %s\n libc %s", pw, salt, got, want)
		}
	}
}

// Typing an administrator password twice must set the hash and move on. The
// account screen collects the name fields first, then uses the same in-process
// sha512-crypt implementation for the password.
func TestAdministratorStepCommitsAHash(t *testing.T) {
	oldRuntime := accountsRuntimeDir
	accountsRuntimeDir = t.TempDir()
	t.Cleanup(func() { accountsRuntimeDir = oldRuntime })

	const pw = "ryoku-install-pw"

	m := model{state: "wizard", flow: steps(), picks: map[string]string{}}
	m.idx = flowIndex(m.flow, "administrator")
	if m.idx <= 0 {
		t.Fatal("the administrator account step is not reachable in the flow")
	}
	m.loadStep()

	type_ := func(s string) {
		for _, r := range s {
			nm, _ := m.onKey(string(r))
			m = nm.(model)
		}
	}
	enter := func() {
		nm, _ := m.onKey("enter")
		m = nm.(model)
	}

	enter() // default username
	enter() // optional full name
	type_(pw)
	enter()
	if m.accounts.adminField != 3 {
		t.Fatalf("first password enter must move to confirm, field = %d (%s)", m.accounts.adminField, m.accounts.adminErr)
	}
	type_(pw + "x")
	enter()
	if m.accounts.adminField != 2 || m.pwHash != "" || m.accounts.adminErr == "" {
		t.Fatalf("a mismatch must re-prompt with an error and no hash (field %d, hash %q, err %q)",
			m.accounts.adminField, m.pwHash, m.accounts.adminErr)
	}

	at := m.idx
	type_(pw)
	enter()
	type_(pw)
	enter()
	if m.accounts.adminErr != "" {
		t.Fatalf("matching passwords were rejected: %s", m.accounts.adminErr)
	}
	if m.picks["username"] != "you" || m.picks["password"] != "set" || m.idx <= at {
		t.Fatalf("a committed password must advance the wizard (user %q, pick %q, idx %d -> %d)",
			m.picks["username"], m.picks["password"], at, m.idx)
	}
	if m.pwHash == "" {
		t.Fatal("the wizard advanced with an empty hash; the backend would die at preflight")
	}

	var hash string
	for _, kv := range m.installEnv() {
		if v, ok := strings.CutPrefix(kv, "RYOKU_PASSWORD_HASH="); ok {
			hash = v
		}
	}
	if hash != m.pwHash {
		t.Fatalf("RYOKU_PASSWORD_HASH = %q, want %q", hash, m.pwHash)
	}
	salt := strings.Split(hash, "$")
	if len(salt) != 4 {
		t.Fatalf("not a sha512-crypt hash: %q", hash)
	}
	if again := sha512Crypt(pw, salt[2]); again != hash {
		t.Errorf("the typed password does not verify against the committed hash:\n %s\n %s", hash, again)
	}
}
