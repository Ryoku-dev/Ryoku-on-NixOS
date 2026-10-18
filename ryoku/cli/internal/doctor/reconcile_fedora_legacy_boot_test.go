package doctor

import (
	"reflect"
	"testing"
)

const testBLS = "/boot/loader/entries/0123"

func TestLegacyBootRemovesConsoleTwinsOnceThePluginIsGone(t *testing.T) {
	entries := []string{
		testBLS + "-7.2.9-200.fc44.x86_64.conf",
		testBLS + "-7.2.9-200.fc44.x86_64~ryokuconsole.conf",
		testBLS + "-7.2.9-200.fc44.x86_64~debug.conf",
		testBLS + "-7.2.7-200.fc44.x86_64~ryokuconsole.conf",
	}
	plan := planLegacyBoot(legacyBootState{entriesRead: true, entries: entries})
	want := []string{entries[1], entries[3]}
	if !reflect.DeepEqual(plan.removeTwins, want) {
		t.Fatalf("twins to remove = %q, want %q", plan.removeTwins, want)
	}

	plan = planLegacyBoot(legacyBootState{pluginPresent: true, entriesRead: true, entries: entries})
	if len(plan.removeTwins) != 0 {
		t.Fatalf("removed twins the installed plugin would only write again: %q", plan.removeTwins)
	}

	plan = planLegacyBoot(legacyBootState{entriesRead: false})
	if !plan.readTwins || plan.markTwins || len(plan.removeTwins) != 0 {
		t.Fatalf("an unreadable /boot/loader/entries should ask for a sudo look and nothing else: %+v", plan)
	}

	plan = planLegacyBoot(legacyBootState{entriesRead: true, entries: entries[:1]})
	if !plan.markTwins || len(plan.removeTwins) != 0 {
		t.Fatalf("a clean look should only be recorded: %+v", plan)
	}

	plan = planLegacyBoot(legacyBootState{twinsChecked: true})
	if !plan.empty() {
		t.Fatalf("entries already checked were looked at again: %+v", plan)
	}
}

func TestLegacyBootRestoresTheBootSuccessTimerOnce(t *testing.T) {
	plan := planLegacyBoot(legacyBootState{twinsChecked: true, timerShipped: true})
	if !plan.enableTimer || !plan.markTimer {
		t.Fatalf("a disabled timer is not restored: %+v", plan)
	}

	plan = planLegacyBoot(legacyBootState{twinsChecked: true, timerShipped: true, timerEnabled: true})
	if plan.enableTimer || !plan.markTimer {
		t.Fatalf("an enabled timer should only be recorded: %+v", plan)
	}

	plan = planLegacyBoot(legacyBootState{twinsChecked: true, timerShipped: true, timerMigrated: true})
	if !plan.empty() {
		t.Fatalf("a timer disabled after the migration was turned on again: %+v", plan)
	}

	plan = planLegacyBoot(legacyBootState{twinsChecked: true})
	if !plan.empty() {
		t.Fatalf("a box without grub2-tools' timer planned work: %+v", plan)
	}
}
