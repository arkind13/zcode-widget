"""Floating panel window (port of FloatingPanelController.swift +
ZCodeWidgetApp.swift): frameless, always-on-top, no taskbar entry,
draggable by the header, with a − (hide) and × (close) button.

Tabs: Tokens (live DB poll), Sessions (re-scanned on open), Google
Sheets sync.
"""

from __future__ import annotations

from PySide6.QtCore import QEvent, QPoint, QSettings, Qt, QTimer
from PySide6.QtGui import QCursor, QIcon, QPainter, QPixmap
from PySide6.QtWidgets import (
    QApplication, QFrame, QHBoxLayout, QLabel, QMainWindow, QSizeGrip,
    QTabWidget, QVBoxLayout, QWidget,
)

from .models_tab import ModelsTab
from .sessions_tab import SessionsTab
from .sync_tab import SyncTab
from .tokens_tab import TokensTab

HEADER_H = 40
EDGE = 8  # resize hot-zone thickness in px


def make_app_icon() -> QIcon:
    """Draw the 'Z' badge programmatically — no binary asset needed."""
    pix = QPixmap(64, 64)
    pix.fill(Qt.transparent)
    p = QPainter(pix)
    p.setRenderHint(QPainter.Antialiasing)
    p.setBrush(Qt.blue)
    p.setPen(Qt.NoPen)
    p.drawRoundedRect(2, 2, 60, 60, 14, 14)
    p.setPen(Qt.white)
    f = p.font()
    f.setBold(True)
    f.setPixelSize(40)
    p.setFont(f)
    p.drawText(pix.rect(), Qt.AlignCenter, "Z")
    p.end()
    return QIcon(pix)


class Toast(QLabel):
    def __init__(self) -> None:
        super().__init__()
        self.setObjectName("toast")
        self.setWindowFlags(Qt.ToolTip | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint)
        self.hide_timer = QTimer(self)
        self.hide_timer.setSingleShot(True)
        self.hide_timer.timeout.connect(self.hide)

    def pop(self, text: str, anchor: QWidget) -> None:
        self.setText(text)
        self.adjustSize()
        geo = anchor.window().geometry()
        top_left = anchor.window().mapToGlobal(
            QPoint(geo.width() // 2 - self.width() // 2, geo.height() - 60)
        )
        self.move(top_left)
        self.show()
        self.raise_()
        self.hide_timer.start(1400)


class _HeaderButton(QLabel):
    """Proper subclass so its handler is guaranteed to run."""

    def __init__(self, text: str, cb) -> None:
        super().__init__(text)
        self._cb = cb
        self.setObjectName("headerBtn")
        self.setFixedSize(24, 24)
        self.setAlignment(Qt.AlignCenter)
        self.setCursor(Qt.PointingHandCursor)

    def mousePressEvent(self, event) -> None:  # noqa: N802
        if event.button() == Qt.LeftButton:
            self._cb()
            event.accept()
            return
        super().mousePressEvent(event)


class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("ZCode Widget")
        self.setWindowFlags(
            Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
        )
        self.resize(560, 580)
        self.setMinimumSize(430, 420)

        self.toast = Toast()
        central = QFrame()
        central.setObjectName("panel")
        self.setCentralWidget(central)
        root = QVBoxLayout(central)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        # -- header (drag handle) ---------------------------------------
        header = QFrame()
        header.setObjectName("header")
        header.setFixedHeight(HEADER_H)
        header_lay = QHBoxLayout(header)
        header_lay.setContentsMargins(12, 0, 8, 0)
        badge = QLabel("Z")
        badge.setObjectName("badge")
        badge.setFixedSize(22, 22)
        badge.setAlignment(Qt.AlignCenter)
        title = QLabel("ZCode Widget")
        title.setObjectName("headerTitle")
        header_lay.addWidget(badge)
        header_lay.addSpacing(6)
        header_lay.addWidget(title)
        header_lay.addStretch(1)

        hide_btn = _HeaderButton("−", self._minimize_to_tray)
        close_btn = _HeaderButton("×", self.close)
        self._header_buttons = (hide_btn, close_btn)
        header_lay.addWidget(hide_btn)
        header_lay.addSpacing(4)
        header_lay.addWidget(close_btn)
        root.addWidget(header)

        # -- tabs --------------------------------------------------------
        self.tabs = QTabWidget()
        self.tabs.setObjectName("tabs")
        self.tokens_tab = TokensTab()
        self.sessions_tab = SessionsTab()
        self.models_tab = ModelsTab()
        self.sync_tab = SyncTab()
        self.tabs.addTab(self.tokens_tab, "Tokens")
        self.tabs.addTab(self.sessions_tab, "Sessions")
        self.tabs.addTab(self.models_tab, "Models")
        self.tabs.addTab(self.sync_tab, "Sheets")
        root.addWidget(self.tabs, 1)

        # -- footer with resize grip --------------------------------------
        footer = QFrame()
        footer.setObjectName("footer")
        footer.setFixedHeight(16)
        footer_lay = QHBoxLayout(footer)
        footer_lay.setContentsMargins(0, 0, 0, 0)
        footer_lay.addStretch(1)
        footer_lay.addWidget(QSizeGrip(footer))
        root.addWidget(footer)

        self.tabs.currentChanged.connect(lambda _: self._refresh_current())

        # live updates: DB poll every 5s for the Tokens tab only; other
        # tabs re-scan when they become current
        self._timer = QTimer(self)
        self._timer.setInterval(5000)
        self._timer.timeout.connect(self.tokens_tab.refresh)
        self._timer.start()

        # resize/move: app-level filter (sees presses before any child)
        # + a cursor poll so border hovers show resize shapes
        QApplication.instance().installEventFilter(self)
        self._cursor_timer = QTimer(self)
        self._cursor_timer.setInterval(100)
        self._cursor_timer.timeout.connect(self._update_cursor)
        self._cursor_timer.start()

        self._restore_geometry()

    # -- behaviour ------------------------------------------------------

    def show_toast(self, text: str) -> None:
        self.toast.pop(text, self)

    def _minimize_to_tray(self) -> None:
        self.hide()

    def toggle(self) -> None:
        if self.isVisible() and not self.isMinimized():
            self.hide()
        else:
            self.showNormal()
            self.raise_()
            self.activateWindow()
            self._refresh_current()

    def _refresh_current(self) -> None:
        w = self.tabs.currentWidget()
        if w is not self.tokens_tab and hasattr(w, "refresh"):
            try:
                w.refresh()
            except Exception:
                pass

    # -- drag / resize ----------------------------------------------------
    # Child widgets swallow most mouse presses before they would ever reach
    # the QMainWindow handlers, so edge/header handling is done in an
    # APPLICATION-level event filter: it sees every press inside the window
    # first and can hijack it for move/resize. Cursor shape is kept in sync
    # with a lightweight poll (tracking hover moves across every child is
    # not practical).

    def _edges_at(self, pos: QPoint) -> Qt.Edges:
        r = self.rect()
        edges = Qt.Edges()
        if pos.y() <= EDGE:
            edges |= Qt.TopEdge
        if r.height() - pos.y() <= EDGE:
            edges |= Qt.BottomEdge
        if pos.x() <= EDGE:
            edges |= Qt.LeftEdge
        if r.width() - pos.x() <= EDGE:
            edges |= Qt.RightEdge
        return edges

    def _cursor_for(self, edges: Qt.Edges) -> Qt.CursorShape:
        left = bool(edges & Qt.LeftEdge)
        right = bool(edges & Qt.RightEdge)
        top = bool(edges & Qt.TopEdge)
        bottom = bool(edges & Qt.BottomEdge)
        if (top and left) or (bottom and right):
            return Qt.SizeFDiagCursor
        if (top and right) or (bottom and left):
            return Qt.SizeBDiagCursor
        if left or right:
            return Qt.SizeHorCursor
        if top or bottom:
            return Qt.SizeVerCursor
        return Qt.ArrowCursor

    def eventFilter(self, obj, event) -> bool:  # noqa: N802
        etype = event.type()
        if etype == QEvent.MouseButtonPress and event.button() == Qt.LeftButton \
                and isinstance(obj, QWidget):
            inside = self.isVisible() and self.isAncestorOf(obj)
            if not inside:
                return super().eventFilter(obj, event)
            pos = self.mapFromGlobal(event.globalPosition().toPoint())
            # let the dedicated controls handle their own clicks
            if isinstance(obj, (QSizeGrip, _HeaderButton)) or \
                    any(isinstance(a, _HeaderButton) for a in self._ancestors(obj)):
                return super().eventFilter(obj, event)
            handle = self.windowHandle()
            edges = self._edges_at(pos)
            if edges and handle:
                handle.startSystemResize(edges)
                return True
            if pos.y() <= HEADER_H and handle:
                handle.startSystemMove()
                return True
        return super().eventFilter(obj, event)

    @staticmethod
    def _ancestors(w: QWidget):
        p = w.parentWidget()
        while p is not None:
            yield p
            p = p.parentWidget()

    def _update_cursor(self) -> None:
        if not self.isVisible():
            return
        local = self.mapFromGlobal(QCursor.pos())
        if self.rect().contains(local) or self.rect().adjusted(-2, -2, 2, 2).contains(local):
            self.setCursor(self._cursor_for(self._edges_at(local)))
        else:
            self.unsetCursor()

    # -- geometry persistence -------------------------------------------

    def _save_geometry(self) -> None:
        s = QSettings("zcode", "zcode-widget-win")
        s.setValue("panel/pos", self.pos())
        s.setValue("panel/size", self.size())

    def _restore_geometry(self) -> None:
        s = QSettings("zcode", "zcode-widget-win")
        size = s.value("panel/size")
        pos = s.value("panel/pos")
        if size is not None:
            self.resize(size)  # respects minimumSize
        if pos is not None:
            self.move(pos)
        else:
            from PySide6.QtGui import QGuiApplication
            screen = QGuiApplication.primaryScreen().availableGeometry()
            self.move(
                screen.right() - self.width() - 24,
                screen.top() + 80,
            )

    def hideEvent(self, event) -> None:  # noqa: N802
        self._save_geometry()
        super().hideEvent(event)

    def closeEvent(self, event) -> None:  # noqa: N802
        self._save_geometry()
        super().closeEvent(event)
