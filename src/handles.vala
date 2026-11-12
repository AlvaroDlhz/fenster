namespace Fenster {
    /* Bordes invisibles para redimensionar cualquier ventana que no traiga los
     * suyos (todas salvo las CSD con márgenes, como Tilix, que los gestionan
     * ellas). Cuatro franjas InputOnly de HANDLE_PX por FUERA de la ventana:
     * nunca tapan contenido. Los extremos de cada franja (HANDLE_CORNER_PX)
     * funcionan como esquina. El cursor cambia según la zona. */
    public class ResizeHandles {
        public const int HANDLE_PX = 6;
        public const int HANDLE_CORNER_PX = 16;

        /* Bordes: 0 arriba, 1 abajo, 2 izquierda, 3 derecha */
        unowned X.Display dpy;
        X.Window wins[4];
        int dirs[4];
        int lengths[4];
        unowned ulong[] cursors;   /* indexado por dirección EWMH (0-7) */
        public bool visible { get; private set; default = false; }

        public ResizeHandles (X.Display dpy, X.Window root, X.Visual visual, ulong[] cursors) {
            this.dpy = dpy;
            this.cursors = cursors;
            var attrs = Xv.SetWindowAttributes ();
            attrs.override_redirect = true;
            attrs.event_mask = Xc.BUTTON_PRESS_MASK | Xc.POINTER_MOTION_MASK;
            for (int i = 0; i < 4; i++) {
                wins[i] = Xv.create_window (dpy, root, -100, -100, 1, 1, 0, 0 /* depth */,
                                            2 /* InputOnly */, visual,
                                            (1 << 9) | (1 << 11) /* OverrideRedirect | EventMask */,
                                            &attrs);
                dirs[i] = -1;
                lengths[i] = 1;
            }
        }

        /* ¿Es una de nuestras franjas? Devuelve el borde (0-3) o -1. */
        public int edge_of (X.Window w) {
            for (int i = 0; i < 4; i++) {
                if (wins[i] == w) return i;
            }
            return -1;
        }

        /* v: rectángulo visible de la ventana (con su barra de Fenster si la lleva). */
        public void place (Rect v) {
            int t = HANDLE_PX;
            Rect[] r = {
                Rect (v.x - t, v.y - t, v.w + 2 * t, t),     /* arriba */
                Rect (v.x - t, v.y + v.h, v.w + 2 * t, t),   /* abajo */
                Rect (v.x - t, v.y, t, v.h),                 /* izquierda */
                Rect (v.x + v.w, v.y, t, v.h)                /* derecha */
            };
            for (int i = 0; i < 4; i++) {
                dpy.move_resize_window (wins[i], r[i].x, r[i].y, int.max (1, r[i].w), int.max (1, r[i].h));
                lengths[i] = i < 2 ? r[i].w : r[i].h;
            }
        }

        public void show () {
            if (!visible) {
                for (int i = 0; i < 4; i++) dpy.map_window (wins[i]);
                visible = true;
            }
        }

        public void hide () {
            if (visible) {
                for (int i = 0; i < 4; i++) dpy.unmap_window (wins[i]);
                visible = false;
            }
        }

        public void raise () {
            for (int i = 0; i < 4; i++) dpy.raise_window (wins[i]);
        }

        public void destroy () {
            hide ();
            for (int i = 0; i < 4; i++) Xx.destroy_window (dpy, wins[i]);
        }

        /* Dirección EWMH de redimensionado según la posición dentro de la franja. */
        public int dir_at (int edge, int lx, int ly) {
            int pos = edge < 2 ? lx : ly;
            bool start = pos < HANDLE_CORNER_PX;
            bool end = pos >= lengths[edge] - HANDLE_CORNER_PX;
            switch (edge) {
            case 0: return start ? DIR_TOPLEFT : end ? DIR_TOPRIGHT : DIR_TOP;
            case 1: return start ? DIR_BOTTOMLEFT : end ? DIR_BOTTOMRIGHT : DIR_BOTTOM;
            case 2: return start ? DIR_TOPLEFT : end ? DIR_BOTTOMLEFT : DIR_LEFT;
            default: return start ? DIR_TOPRIGHT : end ? DIR_BOTTOMRIGHT : DIR_RIGHT;
            }
        }

        /* Cursor acorde a la zona bajo el puntero. */
        public void hover (int edge, int lx, int ly) {
            int d = dir_at (edge, lx, ly);
            if (d != dirs[edge]) {
                dirs[edge] = d;
                Xx.define_cursor (dpy, wins[edge], cursors[d]);
            }
        }
    }
}
