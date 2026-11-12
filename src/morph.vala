namespace Fenster {
    /* Transición de geometría (maximizar, ajustar a mitades/cuartos,
     * restaurar, cambiar de monitor).
     *
     *  1. Se captura la ventana y se cubre con la captura (fotograma idéntico).
     *  2. La ventana real cambia de tamaño y se oculta.
     *  3. La captura se transforma del rectángulo viejo al nuevo (200 ms).
     *  4. Al llegar, la ventana real se muestra DEBAJO de la captura; cuando la
     *     app ya se ha pintado (DAMAGE), la captura se desvanece encima (90 ms):
     *     fundido cruzado entre la imagen estirada y el contenido real.
     *
     * Todo se compone en el servidor X con XRender (captura subida una vez,
     * ventana de tamaño fijo, doble búfer), como la animación de minimizar. */
    public class MorphAnimation {
        public delegate void Reveal ();

        ArgbWindow aw;
        Cairo.ImageSurface snap;
        Rect from;
        Rect to;
        Rect box;
        Reveal? reveal;
        public double radius_from = 0;   /* esquinas antes y después (0 = maximizada) */
        public double radius_to = 0;

        Cairo.Surface? target = null;
        Cairo.Surface? back = null;
        Cairo.Surface? source = null;

        int64 started = 0;
        int64 fade_started = 0;
        uint timer = 0;
        uint hold_timeout = 0;
        bool arrived = false;
        bool painted = false;
        bool fading = false;

        public bool finished { get; private set; default = false; }

        const int MAX_HOLD_MS = 300;

        public MorphAnimation (X.Display dpy, X.Window root, int screen, Atoms atoms,
                               Cairo.ImageSurface snap, Rect from, Rect to, owned Reveal reveal) {
            this.snap = snap;
            this.from = from;
            this.to = to;
            this.reveal = (owned) reveal;
            aw = new ArgbWindow (dpy, root, screen, atoms, "fenster-morph", "Fenster transición");
            int x0 = int.min (from.x, to.x), y0 = int.min (from.y, to.y);
            int x1 = int.max (from.x + from.w, to.x + to.w), y1 = int.max (from.y + from.h, to.y + to.h);
            box = Rect (x0, y0, x1 - x0, y1 - y0);
        }

        public void start () {
            aw.place (box);
            aw.show ();
            target = aw.xlib_surface ();
            back = new Cairo.Surface.similar (target, Cairo.Content.COLOR_ALPHA, box.w, box.h);
            source = new Cairo.Surface.similar (target, Cairo.Content.COLOR_ALPHA,
                                                snap.get_width (), snap.get_height ());
            var up = new Cairo.Context (source);
            up.set_operator (Cairo.Operator.SOURCE);
            up.set_source_surface (snap, 0, 0);
            up.paint ();
            started = get_monotonic_time ();
            draw (0, 1);
            timer = Timeout.add_full (Priority.HIGH, 8, tick);
        }

        bool tick () {
            int64 now = get_monotonic_time ();
            if (fading) {
                double f = (now - fade_started) / (Style.MORPH_FADE_MS * 1000.0);
                if (f >= 1) {
                    timer = 0;
                    finish ();
                    return Source.REMOVE;
                }
                draw (1, 1 - f);
                return Source.CONTINUE;
            }
            double t = (now - started) / (Style.MORPH_MS * 1000.0);
            if (t >= 1) {
                draw (1, 1);
                if (!arrived) {
                    arrived = true;
                    run_reveal ();   /* la ventana real aparece debajo */
                    hold_timeout = Timeout.add (MAX_HOLD_MS, () => {
                        hold_timeout = 0;
                        painted = true;
                        maybe_reveal ();
                        return Source.REMOVE;
                    });
                    maybe_reveal ();
                }
                if (!fading) {
                    timer = 0;
                    return Source.REMOVE;   /* esperando a que la app se pinte */
                }
                return Source.CONTINUE;
            }
            draw (t, 1);
            return Source.CONTINUE;
        }

        public void raise_above () {
            if (!finished) {
                aw.raise ();
            }
        }

        /* La app ya se ha dibujado con su nuevo tamaño (DAMAGE). */
        public void mark_painted () {
            painted = true;
            maybe_reveal ();
        }

        void maybe_reveal () {
            if (finished || fading || !arrived || !painted) {
                return;
            }
            if (hold_timeout != 0) {
                Source.remove (hold_timeout);
                hold_timeout = 0;
            }
            fading = true;
            fade_started = get_monotonic_time ();
            if (timer == 0) {
                timer = Timeout.add_full (Priority.HIGH, 8, tick);
            }
        }

        void run_reveal () {
            if (reveal != null) {
                Reveal r = (owned) reveal;
                reveal = null;
                r ();
            }
        }

        public void finish () {
            if (finished) {
                return;
            }
            finished = true;
            if (timer != 0) {
                Source.remove (timer);
                timer = 0;
            }
            if (hold_timeout != 0) {
                Source.remove (hold_timeout);
                hold_timeout = 0;
            }
            run_reveal ();
            target = null;
            back = null;
            source = null;
            aw.destroy ();
            aw.flush ();
        }

        static double ease_out_cubic (double t) {
            t = double.min (1, double.max (0, t));
            double u = 1 - t;
            return 1 - u * u * u;
        }

        void draw (double t, double alpha) {
            if (back == null) {
                return;
            }
            double e = ease_out_cubic (t);
            double x = from.x + (to.x - from.x) * e - box.x;
            double y = from.y + (to.y - from.y) * e - box.y;
            double w = double.max (1, from.w + (to.w - from.w) * e);
            double h = double.max (1, from.h + (to.h - from.h) * e);

            var cr = new Cairo.Context (back);
            cr.set_operator (Cairo.Operator.CLEAR);
            cr.paint ();
            if (alpha > 0) {
                cr.set_operator (Cairo.Operator.OVER);
                double r = radius_from + (radius_to - radius_from) * e;
                if (r > 0.5) {
                    ArgbWindow.rounded (cr, x, y, w, h, r);
                    cr.clip ();
                }
                cr.translate (x, y);
                cr.scale (w / snap.get_width (), h / snap.get_height ());
                cr.set_source_surface (source, 0, 0);
                cr.get_source ().set_filter (Cairo.Filter.GOOD);
                cr.paint_with_alpha (alpha);
            }
            var fc = new Cairo.Context (target);
            fc.set_operator (Cairo.Operator.SOURCE);
            fc.set_source_surface (back, 0, 0);
            fc.paint ();
            target.flush ();
            aw.flush ();
        }
    }
}
