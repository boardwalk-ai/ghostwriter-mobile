# GhostWriter Mobile

GhostWriter as a standalone Android + iOS app, split out of [boardwalk-ai/Cockpit](https://github.com/boardwalk-ai/Cockpit) PR #18 (original code by RavshanSean).

```
ghostwriter-mobile/
├── app/                    Flutter app (android/ ios/ web/)
└── backend/
    ├── go-api/             HTTP API the app talks to        :8080
    └── python-agent/       LLM agent the Go API calls       :8090
```

App → Go API (`:8080`) → Python agent (`:8090`) → OpenRouter.

## Run locally

**1. Python agent**

```powershell
cd backend/python-agent
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:OPENROUTER_API_KEY="..."        # required
# optional: OPENROUTER_MODEL, GHOSTWRITER_ORCHESTRATOR_MODEL,
#           STEALTHGPT_API_KEY / UNDETECTABLE_API_KEY (humanizer)
uvicorn app.main:app --port 8090 --reload
```

**2. Go API**

```powershell
cd backend/go-api
go run ./cmd/server                  # PORT (default 8080), PYTHON_AGENT_URL (default http://127.0.0.1:8090)
```

**3. App**

```powershell
cd app
flutter run                          # pick emulator / simulator / device
```

## Backend URL

The app uses `http://10.0.2.2:8080` on Android (the emulator's alias for your PC) and
`http://127.0.0.1:8080` on iOS. For a real phone or a deployed backend:

```powershell
flutter run --dart-define=GHOSTWRITER_API_URL=http://192.168.1.50:8080
flutter build apk --release --dart-define=GHOSTWRITER_API_URL=https://api.example.com
```

Plain `http://` only works in debug builds on Android and local network on iOS.
Release builds need an `https://` backend.

## Branches

- `main` — stable
- `dev` — day-to-day work; open pull requests into `dev`

## Not production-ready yet

- Credits are a hard-coded number in `backend/go-api/internal/store/workspace.go`, not OctoCredit.
- Workspaces live in memory and are lost when the Go API restarts.
- No sign-in.
- The research step calls `api.octopilotai.com/api/scrape`.
