namespace Fenster {
    public class Monitor {
        public string name;
        public Rect geom;   /* área física */
        public Rect work;   /* área útil: sin panel ni dock */
        public bool primary;

        public Monitor (string name, Rect geom, bool primary) {
            this.name = name;
            this.geom = geom;
            this.work = geom;
            this.primary = primary;
        }
    }

    /* Monitores activos (RandR 1.5) y su área útil. */
    public class Monitors {
        public GenericArray<Monitor> list = new GenericArray<Monitor> ();
        bool have_randr;

        public Monitors (bool have_randr) {
            this.have_randr = have_randr;
        }

        public void refresh (X.Display dpy, X.Window root, int screen_w, int screen_h) {
            list = new GenericArray<Monitor> ();
            if (have_randr) {
                int n;
                Xrr.MonitorInfo* info = Xrr.get_monitors (dpy, root, true, out n);
                for (int i = 0; i < n; i++) {
                    Xrr.MonitorInfo* m = &info[i];
                    if (m->width <= 0 || m->height <= 0) {
                        continue;
                    }
                    string name = m->name != 0 ? dpy.get_atom_name (m->name) : "monitor-%d".printf (i);
                    list.add (new Monitor (name, Rect (m->x, m->y, m->width, m->height), m->primary));
                }
                if (info != null) {
                    Xrr.free_monitors (info);
                }
            }
            if (list.length <= 1 && Xin.is_active (dpy)) {
                int n;
                Xin.ScreenInfo* xs = Xin.query_screens (dpy, out n);
                if (n > list.length) {
                    list = new GenericArray<Monitor> ();
                    for (int i = 0; i < n; i++) {
                        Xin.ScreenInfo* m = &xs[i];
                        list.add (new Monitor ("xinerama-%d".printf (i),
                                               Rect (m->x_org, m->y_org, m->width, m->height),
                                               i == 0));
                    }
                }
                if (xs != null) {
                    Xx.free (xs);
                }
            }
            if (list.length == 0) {
                list.add (new Monitor ("pantalla", Rect (0, 0, screen_w, screen_h), true));
            }
            /* Orden de izquierda a derecha: hace predecibles los saltos entre monitores */
            list.sort ((a, b) => a.geom.x != b.geom.x ? a.geom.x - b.geom.x : a.geom.y - b.geom.y);
            bool any_primary = false;
            list.foreach ((m) => { any_primary |= m.primary; });
            if (!any_primary) {
                list[0].primary = true;
            }
        }

        public Monitor primary () {
            for (int i = 0; i < list.length; i++) {
                if (list[i].primary) return list[i];
            }
            return list[0];
        }

        /* El monitor que contiene el punto; si ninguno, el más cercano. */
        public Monitor at (int x, int y) {
            Monitor best = list[0];
            long best_d = long.MAX;
            for (int i = 0; i < list.length; i++) {
                var m = list[i];
                if (m.geom.contains (x, y)) {
                    return m;
                }
                long d = m.geom.distance2 (x, y);
                if (d < best_d) {
                    best_d = d;
                    best = m;
                }
            }
            return best;
        }

        public Monitor for_rect (Rect r) {
            return at (r.x + r.w / 2, r.y + r.h / 2);
        }

        public bool covers (int x, int y) {
            for (int i = 0; i < list.length; i++) {
                if (list[i].geom.contains (x, y)) return true;
            }
            return false;
        }

        /* Monitor vecino a la izquierda (-1) o derecha (1), con solape vertical. */
        public Monitor? neighbor (Monitor m, int dir) {
            Monitor? best = null;
            int best_gap = int.MAX;
            for (int i = 0; i < list.length; i++) {
                var o = list[i];
                if (o == m) continue;
                bool overlaps = o.geom.y < m.geom.y + m.geom.h && m.geom.y < o.geom.y + o.geom.h;
                if (!overlaps) continue;
                int gap = dir < 0 ? m.geom.x - (o.geom.x + o.geom.w) : o.geom.x - (m.geom.x + m.geom.w);
                if (gap >= -1 && gap < best_gap) {
                    best_gap = gap;
                    best = o;
                }
            }
            return best;
        }

        /* Aplica los struts (_NET_WM_STRUT_PARTIAL) solo a los monitores que tocan.
         * s = [izq, der, arr, aba, izq_y0, izq_y1, der_y0, der_y1, arr_x0, arr_x1, aba_x0, aba_x1] */
        public void apply_struts (GenericArray<Client> clients, int screen_w, int screen_h) {
            list.foreach ((m) => { m.work = m.geom; });
            clients.foreach ((c) => {
                var s = c.strut;
                list.foreach ((m) => {
                    int left = m.work.x, top = m.work.y;
                    int right = m.work.x + m.work.w, bottom = m.work.y + m.work.h;
                    if (s[0] > 0 && m.geom.intersects (Rect (0, (int) s[4], (int) s[0], (int) (s[5] - s[4] + 1)))) {
                        left = int.max (left, (int) s[0]);
                    }
                    if (s[1] > 0 && m.geom.intersects (Rect (screen_w - (int) s[1], (int) s[6], (int) s[1], (int) (s[7] - s[6] + 1)))) {
                        right = int.min (right, screen_w - (int) s[1]);
                    }
                    if (s[2] > 0 && m.geom.intersects (Rect ((int) s[8], 0, (int) (s[9] - s[8] + 1), (int) s[2]))) {
                        top = int.max (top, (int) s[2]);
                    }
                    if (s[3] > 0 && m.geom.intersects (Rect ((int) s[10], screen_h - (int) s[3], (int) (s[11] - s[10] + 1), (int) s[3]))) {
                        bottom = int.min (bottom, screen_h - (int) s[3]);
                    }
                    if (right - left >= MIN_WORK && bottom - top >= MIN_WORK) {
                        m.work = Rect (left, top, right - left, bottom - top);
                    }
                });
            });
        }
    }
}
