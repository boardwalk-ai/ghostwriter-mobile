# Study Studio

Study Studio as a standalone Flutter app (web + Android + iOS), copied out of
[boardwalk-ai/Cockpit](https://github.com/boardwalk-ai/Cockpit) `main` (`59b5a47`).
It is the same code that runs at https://studystudio.octopilothub.com.

```
studio/
├── lib/                    standalone entrypoint (Study Studio routes only)
├── assets/                 Outfit font + images the module expects the host app to bundle
├── config/                 --dart-define-from-file presets
├── android/ ios/ web/
└── packages/               pub workspace, one pubspec.lock at studio/
    ├── study_studio/       the module: screens, domain, API/SSE client, Firebase auth
    ├── cockpit_ui/         design tokens, theme, shared widgets
    ├── cockpit_core/       config, feature flags, ApiClient
    └── cockpit_module/     CockpitModule contract
```

The app talks to the Study Studio backend at `https://api.octopilothub.com` (FastAPI,
lives in the Cockpit repo under `Backend/`) over SSE, and signs in with Octopilot's
Firebase project.

## Run the dev server

```powershell
cd studio
flutter pub get
flutter run -d chrome --web-port=8765 --dart-define-from-file=config/dev.json
```

Keep port **8765** — it is the localhost origin the API allows through CORS.
`-d web-server --web-port=8765` works too if you want to open the URL yourself.
Sign in with Google from the app to load your studios; without sign-in the API answers `401`.

Other presets:

| Command | Backend |
|---|---|
| `--dart-define-from-file=config/dev.json` | live API + Firebase sign-in |
| `--dart-define-from-file=config/local.json` | a local backend on `http://127.0.0.1:8100`, no Firebase (dev `X-User-Id` auth) |
| no defines | offline, in-memory mock repository |

After changing define values, run `flutter clean` first — otherwise Flutter can reuse
a stale compile with the old values.

The Firebase values in `config/dev.json` are the public web config that already ships
in the live site's JavaScript. There are no server secrets in this folder.

## Tests

Run from the package directory (the widget tests load package assets):

```powershell
cd studio/packages/study_studio
flutter test
```

## Mobile (Android / iOS)

`flutter run` on an emulator or device builds and starts, but **sign-in does not work
on mobile yet**, so the API returns `401` and the screens stay empty:

- `FirebaseAuthService.signIn()` uses `signInWithPopup`, which is web-only. Mobile needs
  `signInWithProvider(GoogleAuthProvider())` (or `google_sign_in`).
- `config/dev.json` carries the **web** Firebase app. Android and iOS apps have to be
  registered in the `octopilot-ai-7b29e` Firebase project (package / bundle id
  `ai.boardwalk.studystudio`, plus the Android SHA-1 fingerprints), and their app IDs
  used on those platforms.

## Known issues (same as Cockpit)

- `buildMockStudios()` in `packages/study_studio/lib/src/data/mock/mock_data.dart`
  returns `[]` on purpose (it was stashed for backend testing), so offline mode shows no
  studios and `home_page_test.dart › shows studio data` fails. The original data is in
  `buildMockStudiosStashed()`.
- Credits are read from the backend but never debited.

## Keeping in sync with Cockpit

This is a copy, not a submodule. To bring in later Cockpit changes, copy
`packages/{study_studio,cockpit_ui,cockpit_core,cockpit_module}` from Cockpit over
`studio/packages/` and run `flutter pub get` + `flutter analyze` here.
