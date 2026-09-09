"""App entry (port of ZCodeWidgetApp.swift): QApplication, dark stylesheet,
system-tray icon with left-click toggle + right-click menu."""

from __future__ import annotations

import sys

from PySide6.QtCore import Qt
from PySide6.QtGui import QAction
from PySide6.QtWidgets import QApplication, QMenu, QSystemTrayIcon

from .ui.main_window import MainWindow, make_app_icon

STYLESHEET = """
QWidget { background: #1b1e27; color: #e6e9f0; font-family: "Segoe UI"; font-size: 9pt; }
#panel, #card { background: #1b1e27; }
#card { background: #242835; border: 1px solid #323748; border-radius: 8px; }
#header { background: #22263380; border-bottom: 1px solid #323748; }
#badge { background: #5b8cff; color: white; border-radius: 6px; font-weight: bold; }
#headerTitle { font-weight: 600; }
#headerBtn { color: #8b91a5; font-size: 13pt; border-radius: 6px; }
#headerBtn:hover { background: #323748; color: #e6e9f0; }
#muted { color: #8b91a5; font-size: 8pt; }
#sectionTitle { color: #8b91a5; font-size: 8pt; font-weight: 600; letter-spacing: 1px; }
#statValue { font-size: 13pt; font-weight: 700; }
QLineEdit, QComboBox, QSpinBox {
    background: #242835; border: 1px solid #323748; border-radius: 6px; padding: 4px 6px;
}
QLineEdit:focus, QComboBox:focus { border-color: #5b8cff; }
QListWidget#itemList, QTableWidget {
    background: #20242f; border: 1px solid #323748; border-radius: 8px; padding: 2px;
}
QTableWidget { font-size: 8pt; }
QTableWidget::item { padding: 1px 4px; border: none; }
QTableWidget::item:selected { background: #33405c; }
QHeaderView::section {
    background: #242835; border: none; border-bottom: 1px solid #323748; padding: 3px 4px; font-size: 8pt;
}
QListWidget#itemList::item { padding: 6px 8px; border-radius: 6px; }
QListWidget#itemList::item:hover { background: #2a2f3e; }
QListWidget#itemList::item:selected { background: #33405c; }
QTabWidget#tabs::pane { border: 1px solid #323748; border-radius: 8px; top: -1px; }
QTabBar::tab {
    background: transparent; color: #8b91a5; padding: 6px 14px; margin-right: 2px;
}
QTabBar::tab:selected { color: #e6e9f0; border-bottom: 2px solid #5b8cff; }
QTabBar::tab:hover { color: #e6e9f0; }
QPushButton {
    background: #2a2f3e; border: 1px solid #323748; border-radius: 6px; padding: 5px 12px;
}
QPushButton:hover { background: #33405c; border-color: #5b8cff; }
QComboBox:disabled { color: #5a5f70; }
QPushButton:default, QPushButton#primaryBtn { background: #5b8cff; border-color: #5b8cff; color: white; }
QPushButton#primaryBtn:hover { background: #6f9aff; }
QCheckBox::indicator, QMenu::indicator { width: 14px; height: 14px; }
#warnLabel { color: #e6b450; font-size: 8pt; }
#errorLabel { color: #ff6b6b; font-size: 8pt; }
#toast {
    background: #33405c; color: #e6e9f0; border: 1px solid #5b8cff;
    border-radius: 8px; padding: 6px 12px; font-size: 9pt;
}
#footer { background: transparent; }
QSizeGrip { background: transparent; width: 14px; height: 14px; }
QScrollBar:vertical { background: transparent; width: 8px; }
QScrollBar::handle:vertical { background: #323748; border-radius: 4px; min-height: 24px; }
QScrollBar::add-line, QScrollBar::sub-line { height: 0; }
QMenu { background: #242835; border: 1px solid #323748; }
QMenu::item:selected { background: #33405c; }
"""


def main() -> int:
    # widget-owned dir for the Google OAuth files
    from . import paths
    paths.WIDGET_DIR.mkdir(parents=True, exist_ok=True)

    app = QApplication(sys.argv)
    app.setApplicationName("zcode-widget-win")
    app.setOrganizationName("zcode")
    app.setQuitOnLastWindowClosed(False)  # closing the panel ≠ quitting
    app.setStyleSheet(STYLESHEET)

    icon = make_app_icon()
    app.setWindowIcon(icon)

    window = MainWindow()

    tray = QSystemTrayIcon(icon)
    tray.setToolTip("ZCode Widget")

    menu = QMenu()
    toggle_action = QAction("Show / Hide panel", menu)
    toggle_action.triggered.connect(window.toggle)
    quit_action = QAction("Quit", menu)
    quit_action.triggered.connect(app.quit)
    menu.addAction(toggle_action)
    menu.addSeparator()
    menu.addAction(quit_action)
    tray.setContextMenu(menu)

    # Left-click toggles the panel; right-click opens the context menu.
    tray.activated.connect(
        lambda reason: window.toggle()
        if reason == QSystemTrayIcon.Trigger
        else None
    )
    tray.show()

    window.toggle()  # show on launch, like `open ZCodeWidget.app`

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
