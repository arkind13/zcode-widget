"""Google Sheets sync tab.

Design (idempotent full reconcile — no duplicates, no stale rows):

  Sheet tab "Sessions" — one row per session whose last activity is
  BEFORE today: id, title, turns, fresh input, output, total,
  first-message time, last-message time.

  Sheet tab "Daily" — one row per calendar day before today: date,
  fresh input, output, total (incl. cache), turns.

  Today is NEVER synced (its numbers keep fluctuating). If an old
  session/topic is resumed today, its new tokens land on today and the
  session stays excluded while it is active today; the first sync after
  it goes quiet refreshes its row. Because every sync rewrites both
  tabs from the DB, rows can never duplicate or go stale — repeated
  syncing is harmless.

Auth: gspread user-OAuth. One-time setup (steps shown in the tab):
put a Google Cloud OAuth *Desktop app* client secret at
~/.zcode-widget/client_secret.json; the first sync opens the browser
for consent and caches the token at ~/.zcode-widget/authorized_user.json.
"""

from __future__ import annotations

import threading

from PySide6.QtCore import Qt, QThread, Signal
from PySide6.QtWidgets import (
    QHBoxLayout, QLabel, QLineEdit, QPushButton, QVBoxLayout, QWidget,
)

from .. import db, paths

MUTED = "#8b91a5"
OK = "#35c07c"
ERR = "#ff6b6b"

DAILY_HEADER = [
    "date", "input_tokens_fresh", "output_tokens",
    "total_tokens_incl_cache", "cached_tokens", "cached_pct_of_input", "turns",
]

SETUP_STEPS = (
    "One-time Google setup (needs your Google account):\n"
    "1. console.cloud.google.com → create/select a project\n"
    "2. APIs & Services → Library → enable “Google Sheets API” and “Google Drive API”\n"
    "3. APIs & Services → OAuth consent screen — opens “Google Auth Platform”.\n"
    "   If it says “not configured yet”, click GET STARTED and fill: App name =\n"
    "   anything (e.g. ZCode Widget), support email = your own, Audience =\n"
    "   External, contact = your own → Create.\n"
    "   Then under AUDIENCE → “Test users” → “+ Add users” → add your Gmail.\n"
    "4. APIs & Services → Credentials → Create credentials → OAuth client ID →\n"
    "   Application type: Desktop app → Create → Download JSON\n"
    f"5. Save the file as:  {paths.WIDGET_DIR / 'client_secret.json'}\n"
    "Then click “Create spreadsheet” or “Sync now” — a browser window opens"
    " once for consent (Google may warn “unverified app” — it is your own app;"
    " Advanced → Allow). After that, syncs are silent."
)

SESSIONS_HEADER = [
    "session_id", "title", "turns", "input_tokens_fresh",
    "output_tokens", "total_tokens_incl_cache", "cached_tokens",
    "cached_pct_of_input", "models", "first_message", "last_message",
]


NUM_FMT = {"numberFormat": {"type": "NUMBER", "pattern": "#,##0"}}
PCT_FMT = {"numberFormat": {"type": "NUMBER", "pattern": "0.0\"%\""}}
DATE_FMT = {"numberFormat": {"type": "DATE", "pattern": "dd-mmm-yyyy"}}
BOLD_FMT = {"textFormat": {"bold": True}}


def _col_letter(n: int) -> str:
    """1-based column index → A1 letter(s)."""
    s = ""
    while n:
        n, r = divmod(n - 1, 26)
        s = chr(65 + r) + s
    return s


def _safe_cell(v):
    """Escape strings Sheets would misread as formulas under USER_ENTERED."""
    if isinstance(v, str) and v[:1] in ("=", "+", "-", "@"):
        return "'" + v
    return v


def build_sync_matrices() -> tuple[list[list], list[list]]:
    """Builds both sheet tab matrices: all history up to yesterday.

    'Sessions': one row per settled session (adds cached tokens/% and the
    models used). 'Daily': one row per day (adds cached tokens/% and one
    column per model seen in the period, holding that day's tokens for it).
    """
    sessions = db.session_summaries(exclude_today=True)
    days = db.daily_totals(days=None, include_today=False)
    dmodel = db.daily_model_usage(days=None, include_today=False)

    sessions_matrix = [SESSIONS_HEADER] + [
        [
            s.session_id, s.title, s.turns, s.input_tokens,
            s.output_tokens, s.computed_total, s.cached,
            round(s.cached_pct, 1), s.models,
            db.format_ms(s.first_ms, "%Y-%m-%d %H:%M"),
            db.format_ms(s.last_ms, "%Y-%m-%d %H:%M"),
        ]
        for s in sessions
    ]

    totals_by_model: dict[str, int] = {}
    for d in dmodel:
        totals_by_model[d.model] = totals_by_model.get(d.model, 0) + d.computed_total
    model_names = sorted(totals_by_model, key=totals_by_model.get, reverse=True)
    per_day_model = {(d.day, d.model): d.computed_total for d in dmodel}

    daily_matrix = [DAILY_HEADER + model_names]
    for d in days:
        denom = d.input_tokens + d.cached
        pct = round(d.cached / denom * 100, 1) if denom else 0
        daily_matrix.append(
            [d.day, d.input_tokens, d.output_tokens, d.computed_total,
             d.cached, pct, d.turns]
            + [per_day_model.get((d.day, m), 0) for m in model_names]
        )
    return sessions_matrix, daily_matrix


def _sheet_id_from(text: str) -> str:
    """Accept a full URL or a bare key."""
    import re
    text = text.strip()
    m = re.search(r"/d/([A-Za-z0-9_-]{20,})", text)
    return m.group(1) if m else text


class _SyncWorker(QThread):
    done = Signal(bool, str)

    def __init__(self, key: str, create_new: bool) -> None:
        super().__init__()
        self.key = key
        self.create_new = create_new

    def run(self) -> None:  # executes off the UI thread
        try:
            import gspread
            gc = gspread.oauth(
                credentials_filename=str(paths.WIDGET_DIR / "client_secret.json"),
                authorized_user_filename=str(paths.WIDGET_DIR / "authorized_user.json"),
            )
            if self.create_new:
                ss = gc.create("ZCode Token Usage")
                key = ss.id
            else:
                key = self.key
                ss = gc.open_by_key(key)

            sessions_matrix, daily_matrix = build_sync_matrices()

            sessions_matrix, daily_matrix = build_sync_matrices()

            # column formats the user wants (survive re-syncs because the
            # sync reapplies them every time)
            s_last = len(sessions_matrix)
            d_last = len(daily_matrix)
            d_cols = len(daily_matrix[0])
            session_fmts = []
            daily_fmts = []
            if s_last > 1:
                session_fmts = [
                    (f"D2:G{s_last}", NUM_FMT),
                    (f"H2:H{s_last}", PCT_FMT),
                ]
            if d_last > 1:
                daily_fmts = [
                    (f"A2:A{d_last}", DATE_FMT),
                    (f"B2:E{d_last}", NUM_FMT),
                    (f"F2:F{d_last}", PCT_FMT),
                ]
                if d_cols > 7:  # per-model columns start at H
                    daily_fmts.append((f"H2:{_col_letter(d_cols)}{d_last}", NUM_FMT))

            self._fill(ss, "Sessions", sessions_matrix, session_fmts)
            self._fill(ss, "Daily", daily_matrix, daily_fmts)
            note = " — spreadsheet created" if self.create_new else ""
            self.done.emit(
                True,
                f"SYNCED:{key}|{len(sessions_matrix) - 1} sessions, "
                f"{len(daily_matrix) - 1} days{note}",
            )
        except Exception as e:  # surfaced verbatim in the status label
            self.done.emit(False, str(e))

    def _fill(self, ss, tab: str, matrix: list[list],
              fmts: list[tuple[str, dict]]) -> None:
        try:
            ws = ss.worksheet(tab)
        except Exception:
            ws = ss.add_worksheet(
                tab, rows=max(len(matrix), 10), cols=len(matrix[0])
            )
        ws.clear()
        # USER_ENTERED so dates ("2026-09-09") become real, formattable dates
        ws.update(
            values=[[_safe_cell(v) for v in row] for row in matrix],
            range_name="A1",
            value_input_option="USER_ENTERED",
        )
        for rng, fmt in fmts:
            ws.format(rng, fmt)
        ws.format(f"A1:{_col_letter(len(matrix[0]))}1", BOLD_FMT)
        ws.freeze(rows=1)


class SyncTab(QWidget):
    def __init__(self) -> None:
        super().__init__()
        from PySide6.QtCore import QSettings
        self._settings = QSettings("zcode", "zcode-widget-win")
        self._worker: _SyncWorker | None = None

        lay = QVBoxLayout(self)
        lay.setContentsMargins(12, 10, 12, 10)
        lay.setSpacing(8)

        title = QLabel("Google Sheets Sync")
        title.setObjectName("sectionTitle")
        lay.addWidget(title)

        expl = QLabel(
            "Exports ALL history up to yesterday:\n"
            "  • tab “Sessions” — tokens per session + first/last message times\n"
            "  • tab “Daily” — token totals per day\n"
            "Today is never synced (still fluctuating). Every sync rebuilds both"
            " tabs from the database, so re-syncing can never duplicate rows, and"
            " an old session resumed later is refreshed on the next sync."
        )
        expl.setObjectName("muted")
        expl.setWordWrap(True)
        lay.addWidget(expl)

        row = QHBoxLayout()
        self.sheet_edit = QLineEdit(self._settings.value("sync/sheet_key", ""))
        self.sheet_edit.setPlaceholderText(
            "Paste a Google Sheets URL or ID (saved automatically)"
        )
        self.sheet_edit.textEdited.connect(
            lambda t: self._settings.setValue("sync/sheet_key", _sheet_id_from(t))
        )
        row.addWidget(self.sheet_edit, 1)
        open_btn = QPushButton("Open")
        open_btn.setToolTip("Open the spreadsheet in your browser")
        open_btn.clicked.connect(self._open_in_browser)
        row.addWidget(open_btn)
        lay.addLayout(row)

        btns = QHBoxLayout()
        self.create_btn = QPushButton("Create spreadsheet")
        self.create_btn.clicked.connect(lambda: self._start(create_new=True))
        self.sync_btn = QPushButton("⟳ Sync now")
        self.sync_btn.setObjectName("primaryBtn")
        self.sync_btn.clicked.connect(lambda: self._start(create_new=False))
        btns.addWidget(self.create_btn)
        btns.addWidget(self.sync_btn)
        btns.addStretch(1)
        lay.addLayout(btns)

        self.status = QLabel("")
        self.status.setObjectName("muted")
        self.status.setWordWrap(True)
        lay.addWidget(self.status)

        lay.addSpacing(4)
        self.help = QLabel(SETUP_STEPS)
        self.help.setObjectName("muted")
        self.help.setWordWrap(True)
        self.help.setTextInteractionFlags(Qt.TextSelectableByMouse)
        lay.addWidget(self.help)
        lay.addStretch(1)

        self._update_help_visibility()

    # -- state ----------------------------------------------------------

    def _update_help_visibility(self) -> None:
        secret = paths.WIDGET_DIR / "client_secret.json"
        token = paths.WIDGET_DIR / "authorized_user.json"
        self.help.setVisible(not (secret.exists() or token.exists()))
        try:
            import gspread  # noqa: F401
        except ImportError:
            self.status.setText(
                "✗ gspread is not installed — run: pip install gspread google-auth-oauthlib"
            )

    def showEvent(self, event) -> None:  # noqa: N802
        self._update_help_visibility()
        super().showEvent(event)

    # -- actions --------------------------------------------------------

    def _open_in_browser(self) -> None:
        import webbrowser
        key = _sheet_id_from(self.sheet_edit.text())
        if key:
            webbrowser.open(f"https://docs.google.com/spreadsheets/d/{key}/edit")
        else:
            webbrowser.open("https://sheets.google.com")

    def _start(self, create_new: bool) -> None:
        if self._worker is not None and self._worker.isRunning():
            return
        paths.WIDGET_DIR.mkdir(parents=True, exist_ok=True)
        if create_new:
            self.sheet_edit.clear()
            self._settings.setValue("sync/sheet_key", "")
        else:
            key = _sheet_id_from(self.sheet_edit.text())
            if not key:
                self._set_status("✗ Paste a spreadsheet URL/ID first (or create one).", err=True)
                return
        self.sync_btn.setEnabled(False)
        self.create_btn.setEnabled(False)
        self._set_status("Syncing…", err=False)

        self._worker = _SyncWorker(
            _sheet_id_from(self.sheet_edit.text()), create_new
        )
        self._worker.done.connect(self._finished)
        self._worker.start()

    def _finished(self, ok: bool, message: str) -> None:
        self.sync_btn.setEnabled(True)
        self.create_btn.setEnabled(True)
        if not ok:
            self._set_status(f"✗ Sync failed: {message}", err=True)
            return
        key, detail = message.split(":", 1)[1].split("|", 1)
        if self._worker is not None and self._worker.create_new:
            self.sheet_edit.setText(key)
            self._settings.setValue("sync/sheet_key", key)
            import webbrowser
            webbrowser.open(f"https://docs.google.com/spreadsheets/d/{key}/edit")
        self._set_status(f"✓ Synced {detail}.", err=False)

    def _set_status(self, text: str, err: bool) -> None:
        self.status.setStyleSheet(f"color: {ERR if err else OK}; font-size: 8pt;")
        self.status.setText(text)
