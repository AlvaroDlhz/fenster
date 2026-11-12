#!/usr/bin/env python3
"""Simula teclado y ratón con XTest para las pruebas automáticas de Fenster.

Uso (sobre $DISPLAY):
  fake-input.py key super+shift+Right      pulsa y suelta una combinación
  fake-input.py hold alt  /  release alt   mantiene / suelta una tecla
  fake-input.py move X Y                   mueve el puntero
  fake-input.py down 1  /  up 1            pulsa / suelta un botón
  fake-input.py pixel WIN X Y              imprime el píxel ARGB de una ventana
"""
import ctypes
import sys
import time

x11 = ctypes.cdll.LoadLibrary("libX11.so.6")
xtst = ctypes.cdll.LoadLibrary("libXtst.so.6")
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
x11.XStringToKeysym.restype = ctypes.c_ulong
x11.XStringToKeysym.argtypes = [ctypes.c_char_p]
x11.XKeysymToKeycode.restype = ctypes.c_ubyte
x11.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
x11.XFlush.argtypes = [ctypes.c_void_p]
x11.XDefaultRootWindow.restype = ctypes.c_ulong
x11.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
x11.XWarpPointer.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_int,
                             ctypes.c_int, ctypes.c_uint, ctypes.c_uint, ctypes.c_int, ctypes.c_int]
x11.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
xtst.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
xtst.XTestFakeButtonEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
xtst.XTestFakeMotionEvent.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]

ALIASES = {"super": "Super_L", "alt": "Alt_L", "shift": "Shift_L", "ctrl": "Control_L"}

dpy = x11.XOpenDisplay(None)
if not dpy:
    sys.exit("no hay display")


def code(name):
    sym = x11.XStringToKeysym(ALIASES.get(name.lower(), name).encode())
    kc = x11.XKeysymToKeycode(dpy, sym)
    if not kc:
        sys.exit(f"tecla desconocida: {name}")
    return kc


def key(k, down):
    xtst.XTestFakeKeyEvent(dpy, code(k), 1 if down else 0, 0)


cmd, args = sys.argv[1], sys.argv[2:]
if cmd == "key":
    parts = args[0].split("+")
    for p in parts:
        key(p, True)
    for p in reversed(parts):
        key(p, False)
elif cmd == "hold":
    key(args[0], True)
elif cmd == "release":
    key(args[0], False)
elif cmd == "move":
    # XWarpPointer funciona también en Xephyr anidado (XTest motion no)
    x11.XWarpPointer(dpy, 0, x11.XDefaultRootWindow(dpy), 0, 0, 0, 0, int(args[0]), int(args[1]))
elif cmd == "pixel":
    x11.XGetImage.restype = ctypes.c_void_p
    x11.XGetImage.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int,
                              ctypes.c_uint, ctypes.c_uint, ctypes.c_ulong, ctypes.c_int]
    x11.XGetPixel.restype = ctypes.c_ulong
    x11.XGetPixel.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
    img = x11.XGetImage(dpy, int(args[0], 0), int(args[1]), int(args[2]), 1, 1,
                        0xFFFFFFFF, 2)  # AllPlanes, ZPixmap
    if not img:
        sys.exit("no se pudo leer la imagen")
    print("%08x" % x11.XGetPixel(img, 0, 0))
    sys.exit(0)
elif cmd in ("down", "up"):
    xtst.XTestFakeButtonEvent(dpy, int(args[0]), 1 if cmd == "down" else 0, 0)
else:
    sys.exit(__doc__)
x11.XSync(dpy, 0)
time.sleep(0.15)
