# ZCode Widget 🪟

A floating, always-on-top desktop widget for [ZCode](https://z.ai) on
**Windows**: live token-usage stats, per-session history, and one-click
sync of your usage history to Google Sheets.

Python 3.10+ · PySide6 · no build step

> Originally a macOS SwiftUI app (`Sources/`, still buildable per the
> [macOS section](#macos-original)); this repo ships the Windows port as
> the primary artifact.

## What's inside

The widget lives in the corner of your screen and in the system tray
(**Z** icon — left-click toggles the panel, right-click for Show/Quit).

### 📊 Tokens
- All-time totals: **fresh input** (cached tokens excluded), output,
  total (incl. cache), turns
- Usage chart with a **7-day / 30-day / monthly** switch
- Last 20 turns with status and in/out tokens
- Live: re-reads the database every 5 seconds

### 🗂 Sessions
- One entry per ZCode session: its **title**, turn count, token counts,
  and **first-message → last-message** times
- Search by title/ID; click a session to copy its ID

### ☁️ Sheets
- One click exports your **entire history up to yesterday** to a Google
  Spreadsheet with two tabs:
  - **Sessions** — `session_id, title, turns, input_tokens_fresh,
    output_tokens, total_tokens_incl_cache, first_message, last_message`
  - **Daily** — `date, input_tokens_fresh, output_tokens,
    total_tokens_incl_cache, turns`
- **Today is never synced** (its numbers are still moving), so you can
  sync as often as you like without churn

## Install

Prerequisite: [Python 3.10+](https://www.python.org/downloads/) — tick
"Add python.exe to PATH" during setup.

```powershell
git clone https://github.com/arkind13/zcode-widget.git
cd zcode-widget\windows
.\install.ps1              # venv + deps + Start Menu shortcut
.\install.ps1 -AddToStartup   # also launch on login
```

Then launch **Start Menu → ZCode Widget**, or run `run.cmd` any time.

### Google Sheets — one-time setup

The sync uses your own Google account via OAuth (your token stays on
your machine):

1. Go to [console.cloud.google.com](https://console.cloud.google.com) → create or select a project
2. **APIs & Services → Library** → enable **Google Sheets API** and **Google Drive API**
3. **APIs & Services → OAuth consent screen** — this opens **Google Auth Platform**. If it says *"not configured yet"*, click **Get started** and fill in: App name (anything, e.g. `ZCode Widget`), support email = your own, Audience = **External**, contact = your own → Create. Then under **Audience → Test users → + Add users**, add your own Gmail address (only test users can grant consent while the app is in Testing status).
4. **APIs & Services → Credentials → Create credentials → OAuth client ID** → application type **Desktop app** → **Download JSON**
5. Save the file as `%USERPROFILE%\.zcode-widget\client_secret.json`

Then open the widget's **Sheets** tab:
- **Create spreadsheet** — makes a new "ZCode Token Usage" spreadsheet
  and remembers it, or paste the URL of an existing one
- **⟳ Sync now** — exports everything up to yesterday (first run opens
  the browser once for Google consent; after that syncs are silent)

## How token numbers are counted

ZCode's `input_tokens` **includes cached tokens** (prompt-cache reads
and writes). Since cached reads are usually ~97% of "input" on long
conversations, this widget reports:

- **Input** = `input_tokens − cache_read − cache_creation` (fresh tokens only)
- **Total** = `computed_total_tokens` (includes cache), always labeled as such

This applies everywhere: stat cards, charts, sessions, and the sheet export.

## Sync semantics (why re-syncing is safe)

Every sync **rebuilds both sheet tabs from the database** — it can never
create duplicates, and stale rows can't survive a sync.

What if an old session/topic gets resumed later and burns more tokens?

- The new turns are timestamped **today**, so they land on today's
  daily bucket — which is never synced while it's still changing.
- The resumed session's row is excluded from sync while it's active
  today (its totals are still moving); the **first sync after it goes
  quiet refreshes that session's row** to its final values.
- Same self-healing applies to daily rows — if a past day's number ever
  changed, the next sync corrects it in place.

## Privacy — what leaves your machine (nothing, by itself)

The repo contains **code only** — no usage data, no credentials, no
tokens. Everything personal lives outside git, on your machine:

| What | Where it lives | Published to GitHub? |
|---|---|---|
| Your usage data | local ZCode DB `~/.zcode/cli/db/db.sqlite` (read-only) | never |
| Your OAuth token | `~/.zcode-widget/authorized_user.json` (created on first sync) | never |
| Your client secret | `~/.zcode-widget/client_secret.json` (you download it yourself) | never |
| Your spreadsheet ID | Windows registry (QSettings) | never |
| Your Google Sheet | **your own Google Drive**, private to you | never |

Each user connects **their own** Google account and syncs to **their
own** spreadsheet (the "Create spreadsheet" button makes it in their
Drive — nothing to share manually). The app has no analytics, no
telemetry, and no server: it reads your local DB, talks only to
Google's Sheets API when *you* click sync, and that's it.

## Data source

Reads `~/.zcode/cli/db/db.sqlite` in SQLite **read-only mode** (it can
never lock or corrupt the DB while ZCode runs). Key tables:
`turn_usage` (per-turn token records, `started_at` is INTEGER
milliseconds since epoch), `session` (titles + timestamps),
`model_usage` (per-API-call records). The widget never writes anywhere
except its own `~/.zcode-widget/` (OAuth token) and the QSettings
registry keys (window position, spreadsheet ID).

## Project structure

```
zcode-widget/
├── README.md
├── windows/                     # ← the Windows app (the focus of this repo)
│   ├── install.ps1              # venv + deps + Start Menu shortcut
│   ├── run.cmd                  # launcher (pythonw, no console)
│   ├── requirements.txt         # PySide6, gspread, google-auth-oauthlib
│   └── zcode_widget/
│       ├── app.py               # QApplication, dark theme, tray icon
│       ├── paths.py             # ~/.zcode + ~/.zcode-widget paths
│       ├── db.py                # read-only queries: totals, daily,
│       │                        #   monthly, sessions, turns
│       └── ui/
│           ├── main_window.py   # frameless always-on-top panel + tray wiring
│           ├── tokens_tab.py    # cards, 7D/30D/monthly chart, turns
│           ├── sessions_tab.py  # per-session history with titles/timings
│           └── sync_tab.py      # Google Sheets reconcile sync
└── Sources/ZCodeWidget/         # the original macOS SwiftUI app
```

## macOS original

The macOS version (floating panel, menu-bar item, skills/plugins/
providers editors) still builds from `Sources/`:

```bash
./install.sh                     # Xcode + xcodegen, installs to /Applications
```

See the original README history and `Sources/ZCodeWidget/` for details.

## Credits

Huge thanks to **[dp2ptrade](https://github.com/dp2ptrade)**, author of the
original macOS app, published by
**[begumporshi-alt](https://github.com/begumporshi-alt)** at
[begumporshi-alt/zcode-widget](https://github.com/begumporshi-alt/zcode-widget).

This repository carries that work forward under the same MIT license: the
Windows port in `windows/` reimplements its data layer and design (the
token-usage schema, the surgical provider editing, the floating-panel
concept), and the untouched macOS sources ship in `Sources/`.

## License

MIT — do whatever you like; attribution appreciated.
