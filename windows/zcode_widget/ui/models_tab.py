"""Models tab: which models consumed what — all-time per-model summary
plus a daily × model breakdown table (token totals include cache)."""

from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QAbstractItemView, QHeaderView, QLabel, QTableWidget,
    QTableWidgetItem, QVBoxLayout, QWidget,
)

from .. import db


class _NumItem(QTableWidgetItem):
    """Displays formatted text but sorts by an underlying numeric value."""

    def __init__(self, text: str, value: float, tip: str = "") -> None:
        super().__init__(text)
        self._value = value
        if tip:
            self.setToolTip(tip)

    def __lt__(self, other) -> bool:  # noqa: N802 (Qt naming)
        if isinstance(other, _NumItem):
            return self._value < other._value
        return super().__lt__(other)


def _cell(text: str, tip: str = "", sort: float | None = None) -> QTableWidgetItem:
    if sort is not None:
        return _NumItem(text, sort, tip)
    item = QTableWidgetItem(text)
    if tip:
        item.setToolTip(tip)
    return item


def _style_table(table: QTableWidget) -> None:
    table.verticalHeader().setVisible(False)
    table.setShowGrid(False)
    table.setSelectionBehavior(QAbstractItemView.SelectRows)
    table.setSelectionMode(QAbstractItemView.SingleSelection)
    table.setEditTriggers(QAbstractItemView.NoEditTriggers)
    table.setWordWrap(False)
    table.setTextElideMode(Qt.ElideRight)
    table.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
    table.verticalHeader().setDefaultSectionSize(22)


class ModelsTab(QWidget):
    def __init__(self) -> None:
        super().__init__()
        lay = QVBoxLayout(self)
        lay.setContentsMargins(12, 10, 12, 10)
        lay.setSpacing(8)

        t1 = QLabel("By model — all time")
        t1.setObjectName("sectionTitle")
        lay.addWidget(t1)

        self.summary_table = QTableWidget(0, 5)
        self.summary_table.setObjectName("sessionsTable")
        self.summary_table.setHorizontalHeaderLabels(["Model", "Calls", "In", "Out", "Total"])
        _style_table(self.summary_table)
        self.summary_table.setColumnWidth(1, 48)
        self.summary_table.setColumnWidth(2, 58)
        self.summary_table.setColumnWidth(3, 52)
        self.summary_table.setColumnWidth(4, 68)
        header = self.summary_table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.Stretch)
        for c in (1, 2, 3, 4):
            header.setSectionResizeMode(c, QHeaderView.Fixed)
        self.summary_table.setFixedHeight(30 + 22 * 2 + 6)
        lay.addWidget(self.summary_table)

        t2 = QLabel("Daily breakdown by model (last 30 days, tokens incl. cache)")
        t2.setObjectName("sectionTitle")
        lay.addWidget(t2)

        self.daily_table = QTableWidget(0, 3)
        self.daily_table.setObjectName("sessionsTable")
        self.daily_table.setHorizontalHeaderLabels(["Day", "Model", "Tokens"])
        _style_table(self.daily_table)
        dheader = self.daily_table.horizontalHeader()
        dheader.setStretchLastSection(False)
        dheader.setSectionResizeMode(0, QHeaderView.Fixed)
        dheader.setSectionResizeMode(2, QHeaderView.Fixed)
        dheader.setSectionResizeMode(1, QHeaderView.Stretch)
        self.daily_table.setColumnWidth(0, 74)
        self.daily_table.setColumnWidth(2, 70)
        lay.addWidget(self.daily_table, 1)

        hint = QLabel("Sorted by day then size · tooltips: calls, fresh input, output")
        hint.setObjectName("muted")
        lay.addWidget(hint)

        self.refresh()

    def refresh(self) -> None:
        try:
            totals = db.model_totals()
            daily = db.daily_model_usage(30)
        except db.DbUnavailable as e:
            self.summary_table.setRowCount(0)
            self.daily_table.setRowCount(0)
            self.summary_table.setRowCount(1)
            self.summary_table.setItem(0, 0, QTableWidgetItem(f"⚠ {e}"))
            return

        # -- all-time summary (one row per model)
        self.summary_table.setSortingEnabled(False)
        self.summary_table.setRowCount(len(totals))
        for r, m in enumerate(totals):
            tip = (
                f"{m.calls} API calls\n"
                f"input fresh: {db.format_tokens(m.input_tokens)}\n"
                f"output: {db.format_tokens(m.output_tokens)}\n"
                f"cached: {db.format_tokens(m.cached)} ({m.cached_pct:.1f}% of input)\n"
                f"total incl. cache: {db.format_tokens(m.computed_total)}"
            )
            self.summary_table.setItem(r, 0, _cell(m.model, tip))
            self.summary_table.setItem(r, 1, _cell(str(m.calls), tip, m.calls))
            self.summary_table.setItem(r, 2, _cell(db.format_tokens(m.input_tokens), tip, m.input_tokens))
            self.summary_table.setItem(r, 3, _cell(db.format_tokens(m.output_tokens), tip, m.output_tokens))
            self.summary_table.setItem(r, 4, _cell(db.format_tokens(m.computed_total), tip, m.computed_total))
        self.summary_table.setSortingEnabled(True)
        self.summary_table.setFixedHeight(30 + 22 * max(1, len(totals)) + 8)

        # -- daily breakdown (one row per day+model pair, biggest first)
        self.daily_table.setRowCount(len(daily))
        for r, d in enumerate(daily):
            tip = (
                f"{d.model}\n{d.calls} API calls\n"
                f"in {db.format_tokens(d.input_tokens)} (fresh) · "
                f"out {db.format_tokens(d.output_tokens)}"
            )
            self.daily_table.setItem(r, 0, _cell(d.day))
            self.daily_table.setItem(r, 1, _cell(d.model, tip))
            self.daily_table.setItem(r, 2, _cell(db.format_tokens(d.computed_total), tip, d.computed_total))
