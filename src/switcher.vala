namespace Fenster {
    /* Una entrada del Alt+Tab: una aplicación y su ventana más reciente. */
    public class SwitcherItem {
        public string key;
        public Client top;
        public int windows = 1;

        public SwitcherItem (string key, Client top) {
            this.key = key;
            this.top = top;
        }
    }

    /* Panel del Alt+Tab al estilo macOS con la estética de Dock-e:
     * negro sólido, esquinas redondeadas, iconos grandes y una "pastilla"
     * translúcida sobre la app seleccionada. Sin texto. Ventana ARGB
     * override-redirect: las esquinas y la animación las compone picom. */
    public class Switcher {
        ArgbWindow aw;
        GenericArray<SwitcherItem> items = new GenericArray<SwitcherItem> ();
        int index = 0;
        int icon_size = Style.SWITCHER_ICON;

        public bool visible {
            get { return aw.visible; }
        }

        public X.Window window {
            get { return aw.window; }
        }

        public Switcher (X.Display dpy, X.Window root, int screen, Atoms atoms) {
            aw = new ArgbWindow (dpy, root, screen, atoms, "fenster-switcher", "Fenster Alt+Tab");
        }

        public void show (GenericArray<SwitcherItem> items, int index, Monitor mon) {
            this.items = items;
            this.index = index;
            layout (mon);
            aw.show ();
            draw ();
        }

        public void select (int index) {
            this.index = index;
            draw ();
        }

        public void hide () {
            aw.hide ();
        }

        void layout (Monitor mon) {
            int n = int.max (items.length, 1);
            int avail = mon.work.w - 2 * 40;
            int pad = Style.SWITCHER_PADDING, cp = Style.SWITCHER_CELL_PADDING, gap = Style.SWITCHER_CELL_GAP;
            /* Si no caben, los iconos encogen (como en macOS) */
            icon_size = Style.SWITCHER_ICON;
            while (icon_size > Style.SWITCHER_ICON_MIN
                   && 2 * pad + n * (icon_size + 2 * cp) + (n - 1) * gap > avail) {
                icon_size -= 4;
            }
            int width = 2 * pad + n * (icon_size + 2 * cp) + (n - 1) * gap;
            int height = 2 * pad + icon_size + 2 * cp;
            aw.place (Rect (mon.work.x + (mon.work.w - width) / 2,
                            mon.work.y + (mon.work.h - height) / 2, width, height));
        }

        public void draw () {
            if (!aw.visible) {
                return;
            }
            int width = aw.width, height = aw.height;
            var img = aw.canvas ();
            var cr = new Cairo.Context (img);
            cr.set_antialias (Cairo.Antialias.BEST);

            /* Panel: negro sólido como Dock-e */
            ArgbWindow.rounded (cr, 0, 0, width, height, Style.SWITCHER_RADIUS);
            cr.set_source_rgba (0, 0, 0, 1);
            cr.fill ();

            int pad = Style.SWITCHER_PADDING, cp = Style.SWITCHER_CELL_PADDING, gap = Style.SWITCHER_CELL_GAP;
            int cell = icon_size + 2 * cp;
            for (int i = 0; i < items.length; i++) {
                double cx = pad + i * (cell + gap);
                double cy = pad;
                if (i == index) {
                    ArgbWindow.rounded (cr, cx, cy, cell, cell, Style.SWITCHER_CELL_RADIUS);
                    cr.set_source_rgba (1, 1, 1, Style.SWITCHER_SELECTED_ALPHA);
                    cr.fill ();
                }
                draw_icon (cr, items[i].top, cx + cp, cy + cp, icon_size);
                /* Punto bajo las apps con varias ventanas (como los indicadores de Dock-e) */
                if (items[i].windows > 1) {
                    cr.arc (cx + cell / 2.0, cy + cell - cp / 2.0, 2, 0, 2 * Math.PI);
                    cr.set_source_rgba (1, 1, 1, 0.55);
                    cr.fill ();
                }
            }

            aw.paint (img);
        }

        void draw_icon (Cairo.Context cr, Client c, double x, double y, int size) {
            if (c.icon != null) {
                int iw = c.icon.get_width (), ih = c.icon.get_height ();
                double scale = (double) size / int.max (iw, ih);
                cr.save ();
                cr.translate (x + (size - iw * scale) / 2, y + (size - ih * scale) / 2);
                cr.scale (scale, scale);
                cr.set_source_surface (c.icon, 0, 0);
                cr.get_source ().set_filter (Cairo.Filter.GOOD);
                cr.paint ();
                cr.restore ();
                return;
            }
            /* Sin icono: cuadrado redondeado con la inicial de la app */
            ArgbWindow.rounded (cr, x + 4, y + 4, size - 8, size - 8, Style.CORNER_RADIUS);
            cr.set_source_rgba (1, 1, 1, 0.10);
            cr.fill ();
            var label = c.wm_class != "" ? c.wm_class.substring (0, 1).up () : "?";
            var fo = new Cairo.FontOptions ();
            fo.set_antialias (Cairo.Antialias.GRAY); /* sin bordes de color en ARGB */
            cr.set_font_options (fo);
            cr.select_font_face ("Inter", Cairo.FontSlant.NORMAL, Cairo.FontWeight.BOLD);
            cr.set_font_size (size * 0.42);
            Cairo.TextExtents ext;
            cr.text_extents (label, out ext);
            cr.move_to (x + (size - ext.width) / 2 - ext.x_bearing, y + (size - ext.height) / 2 - ext.y_bearing);
            cr.set_source_rgba (0.95, 0.95, 0.95, 1);
            cr.show_text (label);
        }
    }
}
