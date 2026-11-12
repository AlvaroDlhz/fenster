namespace Fenster {
    /* Minimizar y restaurar en el sitio, con el mismo lenguaje de movimiento
     * que abrir y cerrar: la ventana encoge al 90 % sobre su centro, baja
     * unos píxeles y se desvanece (restaurar = recorrido inverso).
     *
     * Fenster captura la ventana, la oculta y anima la captura. Para que sea
     * fluida:
     *  · la captura se sube al servidor X UNA vez; cada fotograma se compone
     *    allí con XRender (escalado bilineal, normalmente en GPU);
     *  · la ventana de la animación tiene tamaño fijo: no se redimensiona;
     *  · doble búfer en el servidor: nunca se ve un fotograma a medias;
     *  · hasta 120 fps con progreso por tiempo real y curva ease-out. */
    public class MinimizeAnimation {
        public delegate void Done ();

        ArgbWindow aw;
        Cairo.ImageSurface snap;
        Rect from;
        Rect box;
        bool restoring;
        int64 started = 0;
        uint timer = 0;
        Done? done;

        Cairo.Surface? target = null;   /* la ventana */
        Cairo.Surface? back = null;     /* búfer trasero (servidor) */
        Cairo.Surface? source = null;   /* captura ya en el servidor */

        public bool finished { get; private set; default = false; }

        /* Al restaurar, la captura se queda en su último fotograma hasta que la
         * ventana real ya está dibujada debajo (lo decide el gestor con DAMAGE):
         * así no hay destello entre la captura y la ventana. */
        uint hold_timeout = 0;
        const int MAX_HOLD_MS = 300;

        public MinimizeAnimation (X.Display dpy, X.Window root, int screen, Atoms atoms,
                                  Cairo.ImageSurface snap, Rect window_rect,
                                  bool restoring, owned Done? done) {
            this.snap = snap;
            this.from = window_rect;
            this.restoring = restoring;
            this.done = (owned) done;
            aw = new ArgbWindow (dpy, root, screen, atoms, "fenster-minimize", "Fenster minimizar");
            /* La caja cubre la ventana y su pequeño descenso */
            box = Rect (from.x, from.y, from.w, from.h + Style.MINIMIZE_DROP);
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
            frame (0);
            timer = Timeout.add_full (Priority.HIGH, 8, () => {
                double t = (get_monotonic_time () - started) / (Style.MINIMIZE_ANIM_MS * 1000.0);
                if (t >= 1) {
                    timer = 0;
                    if (restoring) {
                        frame (1);
                        arrive ();
                    } else {
                        finish ();
                    }
                    return Source.REMOVE;
                }
                frame (t);
                return Source.CONTINUE;
            });
        }

        /* Restaurar llegó al final: avisar (el gestor muestra la ventana real
         * debajo) y mantener la captura encima un máximo de MAX_HOLD_MS. */
        void arrive () {
            run_done ();
            if (!finished) {
                hold_timeout = Timeout.add (MAX_HOLD_MS, () => {
                    hold_timeout = 0;
                    finish ();
                    return Source.REMOVE;
                });
            }
        }

        void run_done () {
            if (done != null) {
                Done d = (owned) done;
                done = null;
                d ();
            }
        }

        /* Mantiene la captura por encima de la ventana real mientras se pinta. */
        public void raise_above () {
            if (!finished) {
                aw.raise ();
                aw.flush ();
            }
        }

        /* Termina ya (p. ej. si la ventana desaparece o se repite la acción). */
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
            target = null;
            back = null;
            source = null;
            aw.destroy ();
            run_done ();
            aw.flush ();
        }

        /* Ease-out cúbica: el movimiento se ve desde el primer fotograma y frena
         * al final, tanto al minimizar como al restaurar. */
        static double ease_out_cubic (double t) {
            double u = 1 - t;
            return 1 - u * u * u;
        }

        void frame (double t) {
            if (back == null) {
                return;
            }
            /* e: 0 = ventana normal, 1 = minimizada (pequeña, abajo, invisible) */
            double p = ease_out_cubic (double.min (1, double.max (0, t)));
            double e = restoring ? 1 - p : p;

            double scale = 1 - (1 - Style.MINIMIZE_SCALE) * e;
            double w = from.w * scale, h = from.h * scale;
            double x = (from.w - w) / 2;
            double y = (from.h - h) / 2 + Style.MINIMIZE_DROP * e;
            /* El fundido va algo por delante del encogido: se va antes de "llegar" */
            double alpha = 1 - double.min (1, e * 1.15);

            var cr = new Cairo.Context (back);
            cr.set_operator (Cairo.Operator.CLEAR);
            cr.paint ();
            if (alpha > 0) {
                cr.set_operator (Cairo.Operator.OVER);
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
