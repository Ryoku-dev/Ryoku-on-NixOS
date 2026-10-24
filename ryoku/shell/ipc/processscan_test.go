package main

import (
	"regexp"
	"testing"
)

func TestProcessRecordMatchesPgrepUserAndFullCommandLine(t *testing.T) {
	pattern := regexp.MustCompile(lockClientPattern)
	const ownUID = 1000
	cases := []struct {
		name    string
		status  string
		cmdline string
		want    bool
	}{
		{
			name:    "matching effective user and live client",
			status:  "Name:\tquickshell\nUid:\t1000\t1000\t1000\t1000\n",
			cmdline: "quickshell\x00-p\x00/home/test/.local/share/quickshell-lockscreen/lock_shell.qml\x00",
			want:    true,
		},
		{
			name:    "retained stage path",
			status:  "Uid:\t1000\t1000\t1000\t1000\n",
			cmdline: "quickshell\x00-p\x00/tmp/qylock-next/lockscreen/lock_shell.qml\x00",
			want:    true,
		},
		{
			name:    "effective uid not real uid controls selection",
			status:  "Uid:\t1000\t2000\t1000\t2000\n",
			cmdline: "quickshell\x00-p\x00/home/test/.local/share/quickshell-lockscreen/lock_shell.qml\x00",
			want:    false,
		},
		{
			name:    "substring in one argument still matches joined command line",
			status:  "Uid:\t1000\t1000\t1000\t1000\n",
			cmdline: "sh\x00-c\x00echo quickshell /tmp/quickshell-lockscreen/lock_shell.qml\x00",
			want:    true,
		},
		{
			name:    "similar lock surface is rejected",
			status:  "Uid:\t1000\t1000\t1000\t1000\n",
			cmdline: "quickshell\x00-p\x00/tmp/quickshell-lockscreen/lock.qml\x00",
			want:    false,
		},
		{
			name:    "missing effective uid is rejected",
			status:  "Name:\tquickshell\n",
			cmdline: "quickshell\x00-p\x00/tmp/quickshell-lockscreen/lock_shell.qml\x00",
			want:    false,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := processRecordMatches([]byte(tc.status), []byte(tc.cmdline), ownUID, pattern); got != tc.want {
				t.Fatalf("processRecordMatches = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestSpaceJoinedCmdlinePreservesArgumentBoundaries(t *testing.T) {
	if got, want := spaceJoinedCmdline([]byte("one\x00\x00three\x00")), "one  three"; got != want {
		t.Fatalf("spaceJoinedCmdline = %q, want %q", got, want)
	}
}
