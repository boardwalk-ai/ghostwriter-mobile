# Offline automated tests

These tests use fake HTTP responses, an in-process Python ASGI transport, and
temporary Go loopback servers. No API keys, model subscriptions, running backend,
phone, emulator, or cloud account are required. Dependency installation may need
internet access the first time. The tests themselves do not call live providers.

## Run

From `backend/python-agent` (Python 3.14 is the locally verified version):

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt
.venv\Scripts\python -m unittest discover -s tests -v
```

From `backend/go-api`, with Go 1.27 or later:

```powershell
go test ./... -count=1 -cover
```

From `app`, with Flutter installed:

```powershell
flutter pub get
flutter test --no-pub
flutter analyze --no-pub
```

On this development PC, portable Go is installed at
`$env:LOCALAPPDATA\GhostWriterDev\go\bin\go.exe` if `go` is not on PATH.

## Coverage and isolation

- Python: required model configuration, request construction, provider errors,
  JSON parsing, planning constraints, writer prerequisites and output, research
  filtering and partial failures, revision history and limits, export metadata,
  API health/missing runs, answer validation, and session-isolated memory.
  Environment credentials are cleared for each test and HTTP clients default to
  a transport that fails on unexpected outbound requests.
- Go: malformed requests, missing runs, answer conflicts and upstream errors,
  folder/thread API behavior, event forwarding and run state transitions,
  persistence across store reloads, thread ordering, and credit bounds.
  Every workspace uses `t.TempDir()`; fake agents bind ephemeral loopback ports.
- Flutter: API request payloads, stored conversation decoding, fragmented UTF-8
  event streams, HTTP/JSON failures, empty-prompt behavior, prompt submission,
  displayed questions and start failures. Existing boot and phone-layout tests
  remain included. New tests use `http.runWithClient` and `MockClient`, without
  changing production code for dependency injection.

## Limits

Passing tests validate the behavior exercised by these cases, not live model
quality, provider availability, real-device behavior, release signing, or security
of a deployed system. They do not add authentication or replace the prototype
credit system. The Go server entry point and several workflow branches remain
outside this initial suite. Do not interpret the suite as production certification.

## Verified results (2026-10-10)

- Python: 15 tests passed using the standard-library unittest runner.
- Go: all 8 top-level tests passed, including table-driven subtests. Statement
  coverage: API package 60.0%, store package 80.0%; server entry point 0.0%.
- Flutter: 17 tests passed (13 added, 4 existing).
- Flutter static analysis: no issues found.
- No real API keys or paid service calls were used; no production source changes
  were required.
