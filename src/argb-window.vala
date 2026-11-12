namespace Fenster {
    /* Ventana propia de Fenster con transparencia (visual ARGB de 32 bits),
     * override-redirect y dibujada con cairo. Base del Alt+Tab y de la vista
     * previa del ajuste. picom la compone y la anima como cualquier otra. */
    public class ArgbWindow {
        unowned X.Display dpy;
        X.Window root;
        X.Window win = 0;
        unowned X.Visual? visual = null;
        int depth = 24;

        public int width { get; private set; default = 0; }
        public int height { get; private set; default = 0; }
        public bool visible { get; private set; default = false; }

        public X.Window window {
            get { return win; }
        }

        public ArgbWindow (X.Display dpy, X.Window root, int screen, Atoms atoms,
                           string instance, string title) {
            this.dpy = dpy;
            this.root = root;
            Xv.VisualInfo vi;
            ulong colormap = 0;
            if (Xv.match_visual_info (dpy, screen, 32, 4 /* TrueColor */, out vi) != 0) {
                visual = vi.visual;
                depth = 32;
                colormap = Xv.create_colormap (dpy, root, visual, 0 /* AllocNone */);
            } else {
                /* Sin visual de 32 bits: ventana opaca (sin esquinas transparentes) */
                X.WindowAttributes ra;
                dpy.get_window_attributes (root, out ra);
                visual = ra.visual;
                depth = ra.depth;
            }
            var attrs = Xv.SetWindowAttributes ();
            attrs.override_redirect = true;
            attrs.background_pixel = 0;
            attrs.border_pixel = 0;
            attrs.event_mask = 1L << 15; /* ExposureMask */
            ulong mask = (1 << 1) | (1 << 3) | (1 << 9) | (1 << 11); /* BackPixel BorderPixel OverrideRedirect EventMask */
            if (colormap != 0) {
                attrs.colormap = colormap;
                mask |= 1 << 13; /* CWColormap */
            }
            win = Xv.create_window (dpy, root, -100, -100, 1, 1, 0, depth, 1 /* InputOutput */,
                                    visual, mask, &attrs);

            /* Identificación para picom (reglas y animaciones): clase "Fenster" */
            /* WM_CLASS = "instancia\0Fenster\0" (bytes a mano: las cadenas de Vala
             * se cortan en el primer \0) */
            var cls = new ByteArray ();
            cls.append (instance.data);
            cls.append ({ 0 });
            cls.append ("Fenster".data);
            cls.append ({ 0 });
            Xx.change_property (dpy, win, atoms.wm_class, (X.Atom) 31 /* STRING */, 8,
                                Xc.PROP_MODE_REPLACE, (void*) cls.data, (int) cls.len);
            long[] type = { (long) atoms.net_wm_window_type_utility };
            Xx.change_property (dpy, win, atoms.net_wm_window_type, (X.Atom) Xc.XA_ATOM, 32,
                                Xc.PROP_MODE_REPLACE, (void*) type, 1);
            Xx.change_property (dpy, win, atoms.net_wm_name, atoms.utf8_string, 8,
                                Xc.PROP_MODE_REPLACE, (void*) title.data, title.length);
        }

        public void place (Rect r) {
            width = int.max (r.w, 1);
            height = int.max (r.h, 1);
            dpy.move_resize_window (win, r.x, r.y, width, height);
        }

        public void show () {
            if (!visible) {
                Xv.map_raised (dpy, win);
                visible = true;
            }
        }

        public void hide () {
            if (visible) {
                dpy.unmap_window (win);
                visible = false;
            }
        }

        /* Envía al servidor X lo pendiente: necesario en callbacks de
         * temporizador, fuera del bucle de eventos (que vacía al leer). */
        public void flush () {
            dpy.flush ();
        }

        public void destroy () {
            hide ();
            if (win != 0) {
                Xx.destroy_window (dpy, win);
                win = 0;
            }
        }

        public void raise () {
            if (visible) {
                dpy.raise_window (win);
            }
        }

        /* Coloca la ventana justo debajo de otra (p. ej. la que se arrastra). */
        public void stack_below (X.Window sibling) {
            var wc = X.WindowChanges ();
            wc.sibling = sibling;
            wc.stack_mode = 1; /* Below */
            dpy.configure_window (win, (uint) (Xc.CW_SIBLING | Xc.CW_STACK_MODE), wc);
        }

        /* Superficie cairo de la propia ventana: lo que se dibuje en ella (o en
         * superficies similares) se compone en el servidor X con XRender, sin
         * subir imágenes completas en cada fotograma. */
        public Cairo.Surface xlib_surface () {
            return CairoX.surface_create (dpy, win, visual, width, height);
        }

        /* Lienzo nuevo del tamaño de la ventana (transparente). */
        public Cairo.ImageSurface canvas () {
            return new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
        }

        public void paint (Cairo.ImageSurface img) {
            if (!visible) {
                return;
            }
            var xs = CairoX.surface_create (dpy, win, visual, width, height);
            var xc = new Cairo.Context (xs);
            xc.set_operator (Cairo.Operator.SOURCE);
            xc.set_source_surface (img, 0, 0);
            xc.paint ();
            xs.flush ();
            dpy.flush ();
        }

        public static void rounded (Cairo.Context cr, double x, double y, double w, double h, double r) {
            r = double.min (r, double.min (w, h) / 2);
            cr.new_sub_path ();
            cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
            cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
            cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
            cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
            cr.close_path ();
        }
    }
}
