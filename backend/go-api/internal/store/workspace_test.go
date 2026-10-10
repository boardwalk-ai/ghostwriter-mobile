package store

import (
	"path/filepath"
	"testing"
)

func TestWorkspaceSurvivesRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nested", "workspace.json")
	s := NewWorkspaceStore(path)
	folder := s.CreateFolder("Research")
	thread := s.SaveThread(Thread{Title: "Draft", FolderID: folder.ID, Essay: "First", Sources: []map[string]any{{"url": "https://example.test"}}})
	created := thread.CreatedAt
	thread.Essay = "Revised"
	s.SaveThread(thread)
	s.UseCredits(7)
	restored := NewWorkspaceStore(path).Snapshot()
	if len(restored.Folders) != 1 || restored.Folders[0].ID != folder.ID {
		t.Fatalf("folders not restored: %+v", restored)
	}
	if len(restored.Threads) != 1 || restored.Threads[0].Essay != "Revised" || restored.Threads[0].ID != thread.ID {
		t.Fatalf("thread update lost or duplicated: %+v", restored.Threads)
	}
	if !restored.Threads[0].CreatedAt.Equal(created) || len(restored.Threads[0].Sources) != 1 {
		t.Fatal("thread metadata lost")
	}
	if restored.Credits != 2060 {
		t.Fatalf("credits = %d", restored.Credits)
	}
}

func TestCreditsNeverIncreaseOrBecomeNegative(t *testing.T) {
	s := NewWorkspaceStore(filepath.Join(t.TempDir(), "state.json"))
	if got := s.UseCredits(-10); got != 2067 {
		t.Fatalf("negative charge increased credits: %d", got)
	}
	if got := s.UseCredits(3000); got != 0 {
		t.Fatalf("overdraft: %d", got)
	}
	if got := s.UseCredits(1); got != 0 {
		t.Fatalf("negative balance: %d", got)
	}
}

func TestNewestThreadFirst(t *testing.T) {
	s := NewWorkspaceStore(filepath.Join(t.TempDir(), "state.json"))
	first := s.SaveThread(Thread{Title: "First"})
	second := s.SaveThread(Thread{Title: "Second"})
	got := s.Snapshot().Threads
	if got[0].ID != second.ID || got[1].ID != first.ID {
		t.Fatal("newest thread must come first")
	}
}
