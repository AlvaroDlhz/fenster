namespace Fenster {
    /* Botones de la barra de título, de izquierda a derecha. */
    public enum TitleButton {
        NONE = -1,
        CLOSE = 0,
        MINIMIZE = 1,
        MAXIMIZE = 2
    }

    /* Barra de título de Fenster para las apps que no dibujan la suya
     * (Thunar, Mousepad, xterm, apps Qt…). Estética de Dock-e: negro sólido,
     * título centrado y tres puntos discretos a la DERECHA (– + ✕, cerrar en
     * el extremo) que muestran su símbolo al pasar el ratón. Es una ventana
     * aparte colocada justo encima de la de la app (Fenster no envuelve las
     * ventanas en marcos). */
    public class TitleBar {
        ArgbWindow aw;
        public string title = "";
        public bool active = false;
        public TitleButton hover = TitleButton.NONE;
        public TitleButton pressed = TitleButton.NONE;
        public ulong last_click_time = 0;
        public int radius = Style.CORNER_RADIUS;   /* 0 si la ventana está maximizada */
        int width = 1;

        public X.Window window {
            get { return aw.window; }
        }

        public bool visible {
            get { return aw.visible; }
        }

        public TitleBar (X.Display dpy, X.Window root, int screen, Atoms atoms) {
            aw = new ArgbWindow (dpy, root, screen, atoms, "fenster-titlebar", "Fenster barra");
            aw.select_input (Xc.BUTTON_PRESS_MASK | Xc.BUTTON_RELEASE_MASK
                             | Xc.POINTER_MOTION_MASK | (1L << 5) /* LeaveWindow */);
        }

        /* Coloca la barra sobre el área de la app (geometría del cliente). */
        public void place (Rect client) {
            var r = Rect (client.x, client.y - Style.TITLEBAR_HEIGHT, client.w, Style.TITLEBAR_HEIGHT);
            bool resized = r.w != width;
            width = int.max (1, r.w);
            aw.place (r);
            if (resized) {
                draw ();
            }
        }

        public void show () {
            if (!aw.visible) {
                aw.show ();
                draw ();
            }
        }

        public void set_radius (int r) {
            if (r != radius) {
                radius = r;
                draw ();
            }
        }

        public void hide () {
            aw.hide ();
        }

        public void raise () {
            aw.raise ();
        }

        public void destroy () {
            aw.destroy ();
        }

        /* Centro de cada punto, desde el borde derecho: ✕ en el extremo,
         * luego + y – (orden habitual en Linux/Windows). */
        public static double dot_x (TitleButton b, int w) {
            int slot = b == TitleButton.CLOSE ? 0 : (b == TitleButton.MAXIMIZE ? 1 : 2);
            return w - Style.TITLEBAR_DOT_X - slot * Style.TITLEBAR_DOT_GAP;
        }

        /* Botón bajo una coordenada x local (los tres puntos comparten la zona). */
        public TitleButton button_at (int x, int y) {
            if (y < 0 || y >= Style.TITLEBAR_HEIGHT) {
                return TitleButton.NONE;
            }
            for (int i = 0; i < 3; i++) {
                if (Math.fabs (x - dot_x ((TitleButton) i, width)) <= Style.TITLEBAR_DOT_GAP / 2.0) {
                    return (TitleButton) i;
                }
            }
            return TitleButton.NONE;
        }

        public bool in_buttons_zone (int x) {
            return x > width - (Style.TITLEBAR_DOT_X + 2 * Style.TITLEBAR_DOT_GAP + Style.TITLEBAR_DOT_GAP / 2);
        }

        public void draw () {
            if (!aw.visible) {
                return;
            }
            var img = aw.canvas ();
            render (new Cairo.Context (img), aw.width);
            aw.paint (img);
        }

        /* Dibuja la barra en cualquier contexto (también en las capturas que
         * usan las animaciones, para que la ventana se anime entera). */
        public void render (Cairo.Context cr, int w) {
            int h = Style.TITLEBAR_HEIGHT;
            /* Esquinas superiores redondeadas (el mismo radio que el resto de
             * ventanas); las inferiores las recorta la ventana de la app. */
            double r = double.min (radius, h);
            cr.new_sub_path ();
            cr.move_to (0, h);
            cr.line_to (0, r);
            if (r > 0) cr.arc (r, r, r, Math.PI, 3 * Math.PI / 2);
            cr.line_to (w - r, 0);
            if (r > 0) cr.arc (w - r, r, r, 3 * Math.PI / 2, 2 * Math.PI);
            cr.line_to (w, h);
            cr.close_path ();
            cr.set_source_rgba (0, 0, 0, 1);
            cr.fill ();
            /* separación sutil con el contenido */
            cr.set_source_rgba (1, 1, 1, 0.06);
            cr.rectangle (0, h - 1, w, 1);
            cr.fill ();

            /* Puntos: grises; al pasar por la zona muestran su símbolo */
            bool zone = hover != TitleButton.NONE;
            for (int i = 0; i < 3; i++) {
                double cx = dot_x ((TitleButton) i, w), cy = h / 2.0;
                double a = !active ? 0.18 : (zone ? 0.85 : 0.38);
                if (pressed == (TitleButton) i) a = 1.0;
                cr.arc (cx, cy, Style.TITLEBAR_DOT_R, 0, 2 * Math.PI);
                cr.set_source_rgba (1, 1, 1, a);
                cr.fill ();
                if (zone) {
                    cr.set_source_rgba (0, 0, 0, 0.85);
                    cr.set_line_width (1.4);
                    cr.set_line_cap (Cairo.LineCap.ROUND);
                    double k = 2.6;
                    if (i == 0) {          /* ✕ */
                        cr.move_to (cx - k, cy - k); cr.line_to (cx + k, cy + k);
                        cr.move_to (cx + k, cy - k); cr.line_to (cx - k, cy + k);
                    } else if (i == 1) {   /* – */
                        cr.move_to (cx - k - 0.4, cy); cr.line_to (cx + k + 0.4, cy);
                    } else {               /* + */
                        cr.move_to (cx - k - 0.4, cy); cr.line_to (cx + k + 0.4, cy);
                        cr.move_to (cx, cy - k - 0.4); cr.line_to (cx, cy + k + 0.4);
                    }
                    cr.stroke ();
                }
            }

            /* Título centrado (recortado con «…» si no cabe) */
            var fo = new Cairo.FontOptions ();
            fo.set_antialias (Cairo.Antialias.GRAY);
            cr.set_font_options (fo);
            cr.select_font_face ("Inter", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
            cr.set_font_size (12.5);
            double left = Style.TITLEBAR_DOT_X + 2 * Style.TITLEBAR_DOT_GAP + 18;
            double avail = w - 2 * left;
            var text = title;
            Cairo.TextExtents ext;
            cr.text_extents (text, out ext);
            while (ext.x_advance > avail && text.char_count () > 1) {
                text = text.substring (0, text.index_of_nth_char (text.char_count () - 2)) + "…";
                cr.text_extents (text, out ext);
            }
            if (avail > 20) {
                cr.move_to ((w - ext.x_advance) / 2, h / 2.0 - (ext.y_bearing + ext.height / 2));
                cr.set_source_rgba (0.95, 0.95, 0.95, active ? 0.95 : 0.45);
                cr.show_text (text);
            }
        }
    }
}
