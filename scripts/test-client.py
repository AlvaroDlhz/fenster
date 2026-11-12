#!/usr/bin/env python3
"""Ventanas GTK con comportamientos concretos para las pruebas de Fenster.

  test-client.py nofocus   pide no recibir foco al abrirse (_NET_WM_USER_TIME = 0)
  test-client.py fixed     tamaño fijo (mín = máx)
  test-client.py modal     ventana madre + diálogo modal
  test-client.py urgent    se marca urgente (WM_HINTS) al segundo de abrirse
  test-client.py noicon    sin _NET_WM_ICON y con WM_CLASS de Thunar (como Oboete)
  test-client.py plain-X   ventana normal titulada «prueba-plain-X» (para reglas)
"""
import sys

from gi.repository import GLib

mode = sys.argv[1] if len(sys.argv) > 1 else ""
if mode == "noicon":
    GLib.set_prgname("thunar")  # WM_CLASS = thunar/Thunar → thunar.desktop

import gi  # noqa: E402
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk  # noqa: E402
win = Gtk.Window(title=f"prueba-{mode}")
win.set_default_size(320, 200)
win.connect("destroy", Gtk.main_quit)

if mode == "nofocus":
    win.set_focus_on_map(False)
elif mode == "fixed":
    win.set_resizable(False)
    win.set_size_request(300, 180)
elif mode == "urgent":
    GLib.timeout_add(1000, lambda: (win.set_urgency_hint(True), False)[1])
elif mode == "modal":
    def open_dialog():
        dlg = Gtk.Dialog(title="prueba-dialogo", transient_for=win, modal=True)
        dlg.set_default_size(200, 100)
        dlg.show_all()
        return False
    GLib.timeout_add(300, open_dialog)
elif mode == "noicon":
    Gtk.Window.set_default_icon_list([])
elif mode != "" and not mode.startswith("plain-"):
    sys.exit(__doc__)

win.show_all()
Gtk.main()
