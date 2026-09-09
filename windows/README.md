# ZCode Widget — Windows app

A floating always-on-top desktop widget for **Windows** that mirrors
ZCode's usage DB: live token stats, per-session history, and Google
Sheets sync. See the [root README](../README.md) for the full feature
list, token-counting semantics, and sync design.

## Install

Prerequisite: [Python 3.10+](https://www.python.org/downloads/) — tick
"Add python.exe to PATH" during setup.

```powershell
cd windows
.\install.ps1            # venv + PySide6/gspread + Start Menu shortcut
# launch at login as well:
.\install.ps1 -AddToStartup
```

Launch via the **Start Menu → ZCode Widget**, or run `.\run.cmd`
(add `--console` to see stdout for debugging).

Manual alternative: `pip install PySide6 gspread google-auth-oauthlib`, then `run.cmd`.

## Usage

| Action | How |
|---|---|
| Toggle panel | Left-click the **Z** tray icon (near the clock) |
| Tray menu | Right-click the **Z** icon → Show/Hide, Quit |
| Hide panel | **−** in the header (stays in tray) |
| Close panel | **×** in the header (reopens via tray icon) |
| Switch chart period | Dropdown on the Tokens tab: 7 days / 30 days / monthly |
| Search sessions | Type in the Sessions tab; click a row to copy its ID |
| Sync to Google Sheets | Sheets tab → **⟳ Sync now** (exports up to yesterday) |

Window position is remembered between runs. The Tokens tab polls the
database every 5 seconds; Sessions and Sheets re-scan when opened.

### Google Sheets setup

One-time OAuth setup (steps also shown inside the Sheets tab):

1. [console.cloud.google.com](https://console.cloud.google.com) → create/select a project
2. Enable **Google Sheets API** + **Google Drive API**
3. **OAuth consent screen** now opens **Google Auth Platform** — under **Audience**, personal @gmail.com projects are already *External*; just add yourself under **Test users**
4. Credentials → Create OAuth client ID → **Desktop app** → Download JSON
5. Save as `%USERPROFILE%\.zcode-widget\client_secret.json`

Then **Create spreadsheet** (or paste an existing sheet's URL) and
**⟳ Sync now**. The sheet gets two tabs — **Sessions** (per-session
tokens + first/last message times) and **Daily** (per-day totals).
Today is never synced; every sync rebuilds the tabs, so re-syncing is
harmless and resumed old sessions self-correct.

## Porting notes (macOS → Windows)

| macOS original | Windows port |
|---|---|
| SwiftUI/AppKit floating `NSPanel` + `NSStatusItem` | PySide6 `QMainWindow` with `FramelessWindowHint \| WindowStaysOnTopHint \| Tool` + `QSystemTrayIcon` |
| GRDB (SQLite) | Python stdlib `sqlite3`, URI `mode=ro` |
| FSEvents tail + 5 s DB poll | 5 s DB poll (Windows installs don't write the Stop-hook tail file) |
| `install.sh` (XcodeGen + xcodebuild) | `install.ps1` (venv + pip + Start Menu shortcut) |

This port's tab set differs from the macOS original by request:
Skills / Plugins / Providers tabs were removed; Sessions and Google
Sheets sync were added.

## Resizing

Drag any edge or corner (the cursor changes near the borders), or use
the grip in the bottom-right corner of the panel. Size and position are
remembered across restarts.
