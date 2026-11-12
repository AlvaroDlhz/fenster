/* Bindings de Xlib que faltan (o son incómodas) en x11.vapi de Vala. */
[CCode (cheader_filename = "X11/Xlib.h,X11/Xutil.h,X11/Xatom.h,X11/cursorfont.h")]
namespace Xx {
    [CCode (cname = "XErrorHandler", has_target = false)]
    public delegate int ErrorHandler (X.Display dpy, X.ErrorEvent* ev);

    [CCode (cname = "XSetErrorHandler")]
    public ErrorHandler? set_error_handler (ErrorHandler? handler);

    [CCode (cname = "XSync")]
    public int sync (X.Display dpy, bool discard);

    [CCode (cname = "XKillClient")]
    public int kill_client (X.Display dpy, X.Window w);

    [CCode (cname = "XDefaultScreen")]
    public int default_screen (X.Display dpy);

    [CCode (cname = "XDisplayWidth")]
    public int display_width (X.Display dpy, int screen);

    [CCode (cname = "XDisplayHeight")]
    public int display_height (X.Display dpy, int screen);

    [CCode (cname = "XCreateSimpleWindow")]
    public X.Window create_simple_window (X.Display dpy, X.Window parent, int x, int y,
                                          uint w, uint h, uint border_width,
                                          ulong border, ulong background);

    [CCode (cname = "XCreateFontCursor")]
    public ulong create_font_cursor (X.Display dpy, uint shape);

    [CCode (cname = "XDefineCursor")]
    public int define_cursor (X.Display dpy, X.Window w, ulong cursor);

    [CCode (cname = "XKeysymToKeycode")]
    public uchar keysym_to_keycode (X.Display dpy, ulong keysym);

    [CCode (cname = "XGetWindowProperty")]
    public int get_window_property (X.Display dpy, X.Window w, X.Atom property,
                                    long offset, long length, bool delete,
                                    X.Atom req_type, out X.Atom actual_type,
                                    out int actual_format, out ulong nitems,
                                    out ulong bytes_after, out void* prop);

    [CCode (cname = "XChangeProperty")]
    public int change_property (X.Display dpy, X.Window w, X.Atom property, X.Atom type,
                                int format, int mode, void* data, int nelements);

    [CCode (cname = "XSendEvent")]
    public int send_event (X.Display dpy, X.Window w, bool propagate, long mask, X.Event* ev);

    [CCode (cname = "XFree")]
    public int free (void* data);

    [CCode (cname = "XGrabKeyboard")]
    public int grab_keyboard (X.Display dpy, X.Window w, bool owner_events,
                              int pointer_mode, int keyboard_mode, ulong time);

    [CCode (cname = "XUngrabKeyboard")]
    public int ungrab_keyboard (X.Display dpy, ulong time);

    [CCode (cname = "XRefreshKeyboardMapping")]
    public int refresh_keyboard_mapping (X.Event* ev);

    [CCode (cname = "XGetImage")]
    public X.Image? get_image (X.Display dpy, X.Window d, int x, int y, uint w, uint h,
                               ulong plane_mask, int format);

    [CCode (cname = "XDestroyWindow")]
    public int destroy_window (X.Display dpy, X.Window w);

    [CCode (cname = "XQueryPointer")]
    public bool query_pointer (X.Display dpy, X.Window w, out X.Window root_ret,
                               out X.Window child_ret, out int root_x, out int root_y,
                               out int win_x, out int win_y, out uint mask);
}

/* XRandR 1.5: monitores */
[CCode (cheader_filename = "X11/extensions/Xrandr.h")]
namespace Xrr {
    [CCode (cname = "XRRMonitorInfo", has_type_id = false, destroy_function = "")]
    public struct MonitorInfo {
        public X.Atom name;
        public bool primary;
        public bool automatic;
        public int noutput;
        public int x;
        public int y;
        public int width;
        public int height;
        public int mwidth;
        public int mheight;
    }

    [CCode (cname = "XRRQueryExtension")]
    public bool query_extension (X.Display dpy, out int event_base, out int error_base);

    [CCode (cname = "XRRSelectInput")]
    public void select_input (X.Display dpy, X.Window w, int mask);

    [CCode (cname = "XRRUpdateConfiguration")]
    public int update_configuration (X.Event* ev);

    [CCode (cname = "XRRGetMonitors")]
    public MonitorInfo* get_monitors (X.Display dpy, X.Window w, bool get_active, out int n);

    [CCode (cname = "XRRFreeMonitors")]
    public void free_monitors (MonitorInfo* monitors);

    [CCode (cname = "RRScreenChangeNotifyMask")]
    public const int SCREEN_CHANGE_NOTIFY_MASK;

    [CCode (cname = "RRScreenChangeNotify")]
    public const int SCREEN_CHANGE_NOTIFY;
}

/* Xinerama: alternativa cuando RandR no describe los monitores */
[CCode (cheader_filename = "X11/extensions/Xinerama.h")]
namespace Xin {
    [CCode (cname = "XineramaScreenInfo", has_type_id = false, destroy_function = "")]
    public struct ScreenInfo {
        public int screen_number;
        public short x_org;
        public short y_org;
        public short width;
        public short height;
    }

    [CCode (cname = "XineramaIsActive")]
    public bool is_active (X.Display dpy);

    [CCode (cname = "XineramaQueryScreens")]
    public ScreenInfo* query_screens (X.Display dpy, out int n);
}

/* Ventanas ARGB (transparencia) para la interfaz propia de Fenster */
[CCode (cheader_filename = "X11/Xlib.h,X11/Xutil.h")]
namespace Xv {
    [CCode (cname = "XVisualInfo", has_type_id = false, destroy_function = "")]
    public struct VisualInfo {
        public unowned X.Visual visual;
        public ulong visualid;
        public int screen;
        public int depth;
    }

    [CCode (cname = "XSetWindowAttributes", has_type_id = false, destroy_function = "")]
    public struct SetWindowAttributes {
        public ulong background_pixel;
        public ulong border_pixel;
        public long event_mask;
        public bool override_redirect;
        public ulong colormap;
    }

    [CCode (cname = "XMatchVisualInfo")]
    public int match_visual_info (X.Display dpy, int screen, int depth, int klass, out VisualInfo info);

    [CCode (cname = "XCreateColormap")]
    public ulong create_colormap (X.Display dpy, X.Window w, X.Visual visual, int alloc);

    [CCode (cname = "XCreateWindow")]
    public X.Window create_window (X.Display dpy, X.Window parent, int x, int y, uint w, uint h,
                                   uint border, int depth, uint klass, X.Visual visual,
                                   ulong valuemask, SetWindowAttributes* attrs);

    [CCode (cname = "XMapRaised")]
    public int map_raised (X.Display dpy, X.Window w);
}

[CCode (cheader_filename = "cairo-xlib.h")]
namespace CairoX {
    [CCode (cname = "cairo_xlib_surface_create")]
    public Cairo.Surface surface_create (X.Display dpy, X.Window drawable, X.Visual visual, int w, int h);
}

/* DAMAGE: saber cuándo una ventana ya se ha dibujado (sin destellos) */
[CCode (cheader_filename = "X11/extensions/Xdamage.h")]
namespace Xd {
    [CCode (cname = "XDamageQueryExtension")]
    public bool query_extension (X.Display dpy, out int event_base, out int error_base);

    [CCode (cname = "XDamageCreate")]
    public ulong create (X.Display dpy, X.Window drawable, int level);

    [CCode (cname = "XDamageDestroy")]
    public void destroy (X.Display dpy, ulong damage);

    [CCode (cname = "XDamageReportNonEmpty")]
    public const int REPORT_NON_EMPTY;

    [CCode (cname = "XDamageNotify")]
    public const int NOTIFY;
}

/* SHAPE: recortar las esquinas inferiores de las ventanas con barra de Fenster */
[CCode (cheader_filename = "X11/Xlib.h,X11/extensions/shape.h")]
namespace Xs {
    [CCode (cname = "XRectangle", has_type_id = false, destroy_function = "")]
    public struct Rectangle {
        public short x;
        public short y;
        public ushort width;
        public ushort height;
    }

    [CCode (cname = "XShapeCombineRectangles")]
    public void combine_rectangles (X.Display dpy, X.Window w, int kind, int x_off, int y_off,
                                    [CCode (array_length_pos = 6.1)] Rectangle[] rects,
                                    int op, int ordering);

    [CCode (cname = "XShapeCombineMask")]
    public void combine_mask (X.Display dpy, X.Window w, int kind, int x_off, int y_off,
                              ulong src, int op);

    [CCode (cname = "ShapeBounding")]
    public const int BOUNDING;
    [CCode (cname = "ShapeSet")]
    public const int SET;
    [CCode (cname = "Unsorted")]
    public const int UNSORTED;
}
