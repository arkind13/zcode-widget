"""Tokens tab: stat cards, period-selectable bar chart (7D / 30D /
Monthly), optional exclude-today filter, recent turns list. Chart is
custom-painted to avoid the QtCharts addon.

Input figures EXCLUDE cached tokens everywhere (fresh input only) —
ZCode's DB stores cache reads inside input_tokens, and cache reads
are ~97% of it. Cached tokens get their own card.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from PySide6.QtCore import Qt
from PySide6.QtGui import QColor, QPainter, QPen
from PySide6.QtWidgets import (
    QCheckBox, QComboBox, QFrame, QHBoxLayout, QLabel, QListWidget,
    QListWidgetItem, QVBoxLayout, QWidget,
)

from .. import db

ACCENT = "#5b8cff"
GREEN = "#35c07c"
MUTED = "#8b91a5"


class StatCard(QFrame):
    def __init__(self, title: str, tooltip: str = "") -> None:
        super().__init__()
        self.setObjectName("card")
        if tooltip:
            self.setToolTip(tooltip)
        lay = QVBoxLayout(self)
        lay.setContentsMargins(10, 8, 10, 8)
        lay.setSpacing(2)
        self._title = QLabel(title)
        self._title.setObjectName("muted")
        self._value = QLabel("—")
        self._value.setObjectName("statValue")
        lay.addWidget(self._title)
        lay.addWidget(self._value)

    def set_value(self, value: str) -> None:
        self._value.setText(value)

    def set_title(self, title: str) -> None:
        self._title.setText(title)


class DailyChart(QWidget):
    """Stacked bar chart (fresh input + output) over arbitrary bar labels."""

    def __init__(self) -> None:
        super().__init__()
        self.setMinimumHeight(120)
        self._bars: list[tuple[str, int, int]] = []  # label, in, out
        self._peak_hint = ""

    def set_bars(self, bars: list[tuple[str, int, int]]) -> None:
        self._bars = bars
        peak = max((i + o for _, i, o in bars), default=0)
        self._peak_hint = db.format_tokens(peak) if peak else ""
        self.update()

    def paintEvent(self, event) -> None:  # noqa: N802 (Qt naming)
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        w, h = self.width(), self.height()
        pad_left, pad_right, pad_top, pad_bottom = 8, 8, 14, 16

        peak = max((i + o for _, i, o in self._bars), default=0) or 1

        if self._peak_hint:
            painter.setPen(QPen(QColor(MUTED)))
            painter.drawText(0, 10, self._peak_hint)

        n = len(self._bars) or 1
        slot = (w - pad_left - pad_right) / n
        bar_w = min(slot * 0.62, 26.0)
        chart_h = h - pad_top - pad_bottom

        # thin out x labels when there are many bars
        label_every = max(1, (n + 9) // 10)

        for i, (label, in_tok, out_tok) in enumerate(self._bars):
            x = pad_left + i * slot + (slot - bar_w) / 2
            base_y = h - pad_bottom
            if in_tok + out_tok > 0:
                in_h = chart_h * in_tok / peak
                out_h = chart_h * out_tok / peak
                painter.setPen(Qt.NoPen)
                painter.setBrush(QColor(ACCENT))
                painter.drawRoundedRect(
                    int(x), int(base_y - in_h), int(bar_w), int(in_h) or 1, 2, 2
                )
                painter.setBrush(QColor(GREEN))
                painter.drawRoundedRect(
                    int(x), int(base_y - in_h - out_h), int(bar_w),
                    int(out_h) or 1, 2, 2
                )
            if i % label_every == 0:
                painter.setPen(QPen(QColor(MUTED)))
                painter.drawText(
                    int(pad_left + i * slot), h - 4, int(slot), 12,
                    Qt.AlignHCenter, label,
                )
        painter.end()


PERIODS = ["Last 7 days", "Last 30 days", "Monthly"]


class TokensTab(QWidget):
    def __init__(self) -> None:
        super().__init__()
        lay = QVBoxLayout(self)
        lay.setContentsMargins(12, 10, 12, 10)
        lay.setSpacing(8)

        cards = QHBoxLayout()
        cards.setSpacing(8)
        self.card_in = StatCard("Input", tooltip="Fresh input tokens — cached tokens excluded")
        self.card_cached = StatCard("Cached", tooltip="Cache reads + writes and their share of all input (input includes cache)")
        self.card_out = StatCard("Output")
        self.card_calls = StatCard("Turns")
        for c in (self.card_in, self.card_cached, self.card_out, self.card_calls):
            cards.addWidget(c)
        lay.addLayout(cards)

        self.total_line = QLabel("")
        self.total_line.setObjectName("muted")
        self.total_line.setWordWrap(True)
        lay.addWidget(self.total_line)

        self._error = QLabel("")
        self._error.setObjectName("errorLabel")
        self._error.setWordWrap(True)
        self._error.setVisible(False)
        lay.addWidget(self._error)

        chart_header = QHBoxLayout()
        title1 = QLabel("Usage")
        title1.setObjectName("sectionTitle")
        chart_header.addWidget(title1)
        chart_header.addStretch(1)
        self.today_only = QCheckBox("Today only")
        self.today_only.setToolTip(
            "Show only today's tokens: cards, an hourly chart and today's turns"
        )
        self.today_only.toggled.connect(self._today_toggled)
        chart_header.addWidget(self.today_only)
        self.period = QComboBox()
        self.period.addItems(PERIODS)
        self.period.currentIndexChanged.connect(lambda _: self.refresh())
        chart_header.addWidget(self.period)
        lay.addLayout(chart_header)

        chart_card = QFrame()
        chart_card.setObjectName("card")
        chart_lay = QVBoxLayout(chart_card)
        chart_lay.setContentsMargins(4, 4, 4, 4)
        self.chart = DailyChart()
        chart_lay.addWidget(self.chart)
        lay.addWidget(chart_card)

        title2 = QLabel("Recent Turns")
        title2.setObjectName("sectionTitle")
        lay.addWidget(title2)
        self.turns = QListWidget()
        self.turns.setObjectName("itemList")
        self.turns.setSelectionMode(QListWidget.NoSelection)
        self.turns.setWordWrap(True)
        self.turns.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        lay.addWidget(self.turns, 1)

        self.refresh()

    def _today_toggled(self, on: bool) -> None:
        # the period dropdown only applies to history views
        self.period.setEnabled(not on)
        self.refresh()

    def refresh(self) -> None:
        today_mode = self.today_only.isChecked()
        try:
            totals = db.totals(today_only=today_mode)
        except db.DbUnavailable as e:
            self._error.setText(f"⚠ {e}")
            self._error.setVisible(True)
            return
        self._error.setVisible(False)
        self.card_in.set_value(db.format_tokens(totals.input_fresh))
        denom = totals.input_fresh + totals.cached
        cached_pct = (totals.cached / denom * 100) if denom else 0.0
        self.card_cached.set_value(f"{cached_pct:.0f}%")
        self.card_cached.set_title(f"Cached · {db.format_tokens(totals.cached)}")
        self.card_out.set_value(db.format_tokens(totals.total_output))
        self.card_calls.set_value(str(totals.call_count))
        scope = "today" if today_mode else "all time"
        self.total_line.setText(
            f"Total incl. cached: {db.format_tokens(totals.total_computed)}"
            f" ({scope}) · source: ZCode CLI DB only (~/.zcode/cli/db)"
        )

        try:
            if today_mode:
                bars = [
                    (h.day, h.input_tokens, h.output_tokens)
                    for h in db.hourly_today()
                ]
            elif self.period.currentIndex() == 2:  # Monthly
                months = db.monthly_totals(12)
                bars = [(m.month, m.input_tokens, m.output_tokens) for m in months]
            else:
                days = 7 if self.period.currentIndex() == 0 else 30
                rows = {d.day: d for d in db.daily_totals(days)}
                today = datetime.now().date()
                bars = []
                for i in range(days - 1, -1, -1):
                    day = today - timedelta(days=i)
                    d = rows.get(day.strftime("%Y-%m-%d"))
                    bars.append((
                        day.strftime("%m-%d"),
                        d.input_tokens if d else 0,
                        d.output_tokens if d else 0,
                    ))
            self.chart.set_bars(bars)
            turns = db.recent_turns(50 if today_mode else 20, today_only=today_mode)
        except db.DbUnavailable:
            return

        self.turns.clear()
        for t in reversed(turns):  # oldest first, chart-like ordering
            when = db.format_ms(t["started_at"])
            mark = "✓" if t["status"] == "completed" else t["status"] or "?"
            row = QListWidgetItem(
                f"{mark}  {when}   "
                f"{db.format_tokens(t['input'])} in → "
                f"{db.format_tokens(t['output'])} out"
            )
            row.setToolTip(
                f"session {t['session_id'][:8]} · turn {t['turn_id'][:8]}\n"
                f"{t['requests']} model requests · "
                f"{t['tools']} tool calls · "
                f"{t['duration_ms'] / 1000:.1f}s"
            )
            self.turns.addItem(row)
