#!/usr/bin/env python3
# Copyright 2020 Jiří Janoušek <janousek.jiri@gmail.com>
# Licensed under BSD-2-Clause license - see file LICENSE.
import os
import signal
import sys
from typing import List

from PySide2.QtCore import QUrl
from PySide2.QtWidgets import QApplication

from wevf.client import Client
from wevf.utils import get_data_path

WAYLAND_DISPLAY = os.environ.get("DEMO_DISPLAY", os.environ.get("WAYLAND_DISPLAY", "wevf-demo"))


def run(argv: List[str]):
    signal.signal(signal.SIGINT, signal.SIG_DFL)

    app = QApplication(argv)
    qml_view = QUrl(os.fspath(get_data_path("view.qml")))
    client = Client(WAYLAND_DISPLAY, qml_view)
    client.connect()
    client.attach()
    client.wl_display.dispatch()

    code = app.exec_()
    sys.exit(code)


run(sys.argv)
