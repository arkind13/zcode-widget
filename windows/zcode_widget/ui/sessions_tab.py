"""Sessions tab: sortable table of all ZCode sessions — condensed title,
turns, fresh-input/output/total tokens, cached %, models used, and
first→last message times. Double-click a row to copy the session ID."""

from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtGui import QGuiApplication
from PySide6.QtWidgets import (
    QAbstractItemView, QHeaderView, QLabel, QLineEdit, QTableWidget,
    QTableWidgetItem, QVBoxLayout, QWidget,
)

from .. import db

MAX_TITLE = 30
MAX_MODELS = 22

COLS = ["Session", "Turns", "In", "Out", "Total", "Cache", "When", "Models"]


def _condense(text: str, max_len: int) -> str:
    t = " ".join(text.split())  # collapse whitespace/newlines
    if len(t) > max_len:
        t = t[: max_len - 1].rstrip() + "…"
    return t or "(untitled)"


class _NumItem(QTableWidgetItem):
    """Displays formatted text but sorts by an underlying numeric value."""

    def __init__(self, text: str, value: float, tip: str) -> None:
        super().__init__(text)
        self._value = value
        self.setToolTip(tip)

    def __lt__(self, other) -> bool:  # noqa: N802 (Qt naming)
        if isinstance(other, _NumItem):
            return self._value < other._value
        return super().__lt__(other)


class SessionsTab(QWidget):
    def __init__(self) -> None:
        super().__init__()
        lay = QVBoxLayout(self)
        lay.setContentsMargins(12, 10, 12, 10)
        lay.setSpacing(8)

        self.search = QLineEdit()
        self.search.setPlaceholderText("Search sessions…")
        self.search.setClearButtonEnabled(True)
        self.search.textChanged.connect(self._apply_filter)
        lay.addWidget(self.search)

        self.table = QTableWidget(0, len(COLS))
        self.table.setObjectName("sessionsTable")
        self.table.setHorizontalHeaderLabels(COLS)
        self.table.verticalHeader().setVisible(False)
        self.table.setShowGrid(False)
        self.table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.SingleSelection)
        self.table.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.table.setWordWrap(False)
        self.table.setTextElideMode(Qt.ElideRight)
        self.table.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.table.verticalHeader().setDefaultSectionSize(24)
        self.table.itemDoubleClicked.connect(self._on_double_click)

        header = self.table.horizontalHeader()
        header.setStretchLastSection(False)
        header.setSectionResizeMode(1, QHeaderView.Fixed)
        header.setSectionResizeMode(2, QHeaderView.Fixed)
        header.setSectionResizeMode(3, QHeaderView.Fixed)
        header.setSectionResizeMode(4, QHeaderView.Fixed)
        header.setSectionResizeMode(5, QHeaderView.Fixed)
        header.setSectionResizeMode(6, QHeaderView.Fixed)
        header.setSectionResizeMode(0, QHeaderView.Stretch)  # Session
        header.setSectionResizeMode(7, QHeaderView.Stretch)  # Models
        self.table.setColumnWidth(1, 34)   # Turns
        self.table.setColumnWidth(2, 50)   # In
        self.table.setColumnWidth(3, 50)   # Out
        self.table.setColumnWidth(4, 56)   # Total
        self.table.setColumnWidth(5, 48)   # Cache %
        self.table.setColumnWidth(6, 90)   # When (first → last)
        lay.addWidget(self.table, 1)

        self.summary = QLabel("")
        self.summary.setObjectName("muted")
        self.summary.setWordWrap(True)
        lay.addWidget(self.summary)

        hint = QLabel(
            "Double-click a row to copy its session ID · In = fresh (cache excluded) · "
            "Cache = share of input from cache · full titles/models in tooltips · click headers to sort"
        )
        hint.setObjectName("muted")
        hint.setWordWrap(True)
        lay.addWidget(hint)

        self._session_ids: list[str] = []
        self.refresh()

    def refresh(self) -> None:
        try:
            sessions = db.session_summaries()
        except db.DbUnavailable as e:
            self.table.setRowCount(0)
            self.summary.setText(f"⚠ {e}")
            return

        self.table.setSortingEnabled(False)
        self.table.setRowCount(len(sessions))
        self._session_ids = []
        for r, s in enumerate(sessions):
            self._session_ids.append(s.session_id)
            full = (
                f"{s.session_id}\n"
                f"title: {s.title or '(untitled)'}\n"
                f"models: {s.models or '?'}\n"
                f"cached: {db.format_tokens(s.cached)} of input ({s.cached_pct:.1f}%)\n"
                f"first message: {db.format_ms(s.first_ms, '%Y-%m-%d %H:%M:%S')}\n"
                f"last message:  {db.format_ms(s.last_ms, '%Y-%m-%d %H:%M:%S')}"
            )

            def cell(text: str, tip: str, sort: float | None = None) -> QTableWidgetItem:
                if sort is not None:
                    return _NumItem(text, sort, tip)
                item = QTableWidgetItem(text)
                item.setToolTip(tip)
                return item

            same_day = db.format_ms(s.first_ms, '%m-%d') == db.format_ms(s.last_ms, '%m-%d')
            when = (
                f"{db.format_ms(s.first_ms, '%H:%M')}→{db.format_ms(s.last_ms, '%H:%M')}"
                if same_day
                else f"{db.format_ms(s.first_ms, '%m-%d')}→{db.format_ms(s.last_ms, '%m-%d')}"
            )
            self.table.setItem(r, 0, cell(_condense(s.title_or_id, MAX_TITLE), full))
            self.table.setItem(r, 1, cell(str(s.turns), full, s.turns))
            self.table.setItem(r, 2, cell(db.format_tokens(s.input_tokens), full, s.input_tokens))
            self.table.setItem(r, 3, cell(db.format_tokens(s.output_tokens), full, s.output_tokens))
            self.table.setItem(r, 4, cell(db.format_tokens(s.computed_total), full, s.computed_total))
            self.table.setItem(r, 5, cell(f"{s.cached_pct:.0f}%", full, s.cached_pct))
            self.table.setItem(r, 6, cell(when, full, s.first_ms))
            self.table.setItem(r, 7, cell(_condense(s.models or "?", MAX_MODELS), full))
        self.table.setSortingEnabled(True)

        total_in = sum(s.input_tokens for s in sessions)
        total_out = sum(s.output_tokens for s in sessions)
        self.summary.setText(
            f"{len(sessions)} sessions · "
            f"{db.format_tokens(total_in)} fresh in · "
            f"{db.format_tokens(total_out)} out"
        )
        self._apply_filter(self.search.text())

    def _apply_filter(self, text: str) -> None:
        q = text.strip().lower()
        for r in range(self.table.rowCount()):
            title_item = self.table.item(r, 0)
            models_item = self.table.item(r, 7)
            hay = " ".join(
                x.text().lower() for x in (title_item, models_item) if x
            )
            sid = self._session_ids[r] if r < len(self._session_ids) else ""
            self.table.setRowHidden(r, bool(q) and q not in hay and q not in sid.lower())

    def _on_double_click(self, item: QTableWidgetItem) -> None:
        row = item.row()
        if 0 <= row < len(self._session_ids):
            QGuiApplication.clipboard().setText(self._session_ids[row])
