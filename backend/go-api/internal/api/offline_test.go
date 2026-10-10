package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"ghostwriter-backend/go-api/internal/models"
	"ghostwriter-backend/go-api/internal/store"
)

func testServer(t *testing.T) *Server {
	t.Helper()
	// Unmocked agent calls fail locally; never fall back to the user's running service.
	t.Setenv("PYTHON_AGENT_URL", "http://127.0.0.1:0")
	return &Server{Runs: store.NewRunStore(), Workspace: store.NewWorkspaceStore(filepath.Join(t.TempDir(), "state.json"))}
}

func request(s *Server, method, path, body string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	s.Routes().ServeHTTP(w, httptest.NewRequest(method, path, strings.NewReader(body)))
	return w
}

func TestValidation(t *testing.T) {
	s := testServer(t)
	cases := []struct {
		method, path, body string
		status             int
	}{
		{"POST", "/api/ghostwriter/start", "{", 400},
		{"POST", "/api/ghostwriter/folders", "{", 400},
		{"POST", "/api/ghostwriter/folders", `{"name":"  "}`, 400},
		{"POST", "/api/ghostwriter/threads", "{", 400},
		{"POST", "/api/ghostwriter/answer", `{}`, 400},
		{"POST", "/api/ghostwriter/answer", `{"runId":"missing","field":"x"}`, 404},
		{"POST", "/api/ghostwriter/cancel", `{}`, 400},
		{"POST", "/api/ghostwriter/cancel", `{"runId":"missing"}`, 404},
		{"POST", "/api/ghostwriter/pause", `{}`, 400},
		{"GET", "/api/ghostwriter/run", "", 400},
		{"GET", "/api/ghostwriter/run?runId=missing", "", 404},
	}
	for i, c := range cases {
		t.Run(fmt.Sprint(i), func(t *testing.T) {
			w := request(s, c.method, c.path, c.body)
			if w.Code != c.status {
				t.Fatalf("%s: got %d: %s", c.path, w.Code, w.Body)
			}
		})
	}
	if s.Workspace.Snapshot().Credits != 2067 {
		t.Fatal("invalid requests consumed credits")
	}
}

func TestFolderAndThreadRoutes(t *testing.T) {
	s := testServer(t)
	w := request(s, "POST", "/api/ghostwriter/folders", `{"name":" Research "}`)
	var folder store.Folder
	if err := json.Unmarshal(w.Body.Bytes(), &folder); err != nil {
		t.Fatal(err)
	}
	if w.Code != 201 || folder.Name != "Research" || folder.ID == "" {
		t.Fatalf("folder: %s", w.Body)
	}
	w = request(s, "POST", "/api/ghostwriter/threads", `{"title":" ","essay":"Saved essay"}`)
	var thread store.Thread
	if err := json.Unmarshal(w.Body.Bytes(), &thread); err != nil {
		t.Fatal(err)
	}
	if thread.Title != "Untitled GhostWriter Essay" || thread.Status != "Finished" {
		t.Fatalf("defaults: %+v", thread)
	}
	w = request(s, "GET", "/api/ghostwriter/workspace", "")
	var state store.WorkspaceState
	if err := json.Unmarshal(w.Body.Bytes(), &state); err != nil {
		t.Fatal(err)
	}
	if len(state.Threads) != 1 || state.Threads[0].Essay != "Saved essay" {
		t.Fatalf("workspace: %+v", state)
	}
}

func TestAnswerForwardingAndFailure(t *testing.T) {
	for _, fail := range []bool{false, true} {
		t.Run(fmt.Sprint(fail), func(t *testing.T) {
			s := testServer(t)
			run := &models.Run{ID: "test", PendingField: "wordCount", Events: make(chan models.AgentEvent, 8)}
			s.Runs.Create(run)
			calls := 0
			upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				calls++
				if r.URL.Path != "/runs/test/answer" || r.Method != "POST" {
					t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
				}
				var body map[string]any
				if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
					t.Error(err)
				}
				if body["field"] != "wordCount" || body["value"] != float64(500) {
					t.Errorf("payload: %+v", body)
				}
				if fail {
					http.Error(w, "upstream unavailable", 503)
				} else {
					fmt.Fprint(w, `{"ok":true}`)
				}
			}))
			defer upstream.Close()
			t.Setenv("PYTHON_AGENT_URL", upstream.URL)
			wrong := request(s, "POST", "/api/ghostwriter/answer", `{"runId":"test","field":"wrong","value":500}`)
			if wrong.Code != 409 || calls != 0 {
				t.Fatal("wrong question forwarded")
			}
			w := request(s, "POST", "/api/ghostwriter/answer", `{"runId":"test","field":"wordCount","value":500}`)
			if fail {
				if w.Code != 502 || run.PendingField != "wordCount" {
					t.Fatalf("failed answer lost pending question: %s", w.Body)
				}
			} else {
				if w.Code != 200 || run.PendingField != "" {
					t.Fatalf("answer not accepted: %s", w.Body)
				}
			}
		})
	}
}

func TestPythonStreamUpdatesState(t *testing.T) {
	for _, kind := range []string{"question", "done", "fatal"} {
		t.Run(kind, func(t *testing.T) {
			s := testServer(t)
			upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				fmt.Fprintf(w, ": heartbeat\n\ndata: invalid-json\n\ndata: {"+`"type":%q,"field":"wordCount"`+"}\n\n", kind)
			}))
			defer upstream.Close()
			t.Setenv("PYTHON_AGENT_URL", upstream.URL)
			run := &models.Run{ID: "test", Events: make(chan models.AgentEvent, 8)}
			s.streamPythonEvents(run)
			if len(run.Events) != 1 {
				t.Fatalf("unexpected events: %d", len(run.Events))
			}
			event := <-run.Events
			if event.Type != kind {
				t.Fatalf("event: %+v", event)
			}
			switch kind {
			case "question":
				if run.Status != models.RunWaitingForUser || run.PendingField != "wordCount" {
					t.Fatal("question state missing")
				}
			case "done":
				if !run.Finished || run.Status != models.RunFinished {
					t.Fatal("completion state missing")
				}
			case "fatal":
				if !run.Finished || run.Status != models.RunError {
					t.Fatal("error state missing")
				}
			}
		})
	}
}

func TestPythonStartFailureEmitsFatal(t *testing.T) {
	s := testServer(t)
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Error(w, "agent unavailable", 503) }))
	defer upstream.Close()
	t.Setenv("PYTHON_AGENT_URL", upstream.URL)
	run := &models.Run{ID: "test", Events: make(chan models.AgentEvent, 8)}
	s.startPythonAgent(run)
	select {
	case event := <-run.Events:
		if event.Type != "fatal" || !strings.Contains(event.Error, "agent unavailable") {
			t.Fatalf("event: %+v", event)
		}
	default:
		t.Fatal("missing failure event")
	}
}
