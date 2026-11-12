/* Redimensionado enlazado: al cambiar el tamaño de una ventana, las que están
 * pegadas a ella se ajustan a la vez y el borde común se mueve como una
 * sola línea (como Windows 11 o un gestor en mosaico).
 *
 *  · vecinas: su borde toca el borde que se arrastra (al otro lado);
 *  · hermanas: están del mismo lado, alineadas con ese borde y tocan a
 *    alguna vecina (p. ej. dos cuartos apilados frente a una mitad).
 *
 * Todo se calcula con el rectángulo VISIBLE (sin los márgenes de sombra de
 * las apps CSD) y respetando el tamaño mínimo de cada ventana. */
namespace Fenster {
    public class ResizeLink {
        public Client c;
        public Rect start;      /* rectángulo visible al empezar */
        public int h_edge = 0;  /* -1 se mueve su borde izq., 1 el der., 0 ninguno */
        public int h_src = 0;   /* sigue al borde -1 izq. / 1 der. de la activa */
        public int v_edge = 0;  /* -1 superior, 1 inferior */
        public int v_src = 0;

        public ResizeLink (Client c, Rect start) {
            this.c = c;
            this.start = start;
        }
    }

    namespace LinkedResize {
        public const int TOLERANCE = 12;    /* px entre bordes para considerarlos pegados */
        public const int MIN_OVERLAP = 40;  /* px que deben compartir */

        public Rect visible (Client c, Rect g) {
            return Rect (g.x + (int) c.csd[0], g.y + (int) c.csd[2],
                         g.w - (int) (c.csd[0] + c.csd[1]), g.h - (int) (c.csd[2] + c.csd[3]));
        }

        public int min_w (Client c) {
            return int.max (64, c.hints.min_w - (int) (c.csd[0] + c.csd[1]));
        }

        public int min_h (Client c) {
            return int.max (64, c.hints.min_h - (int) (c.csd[2] + c.csd[3]));
        }

        int overlap (int a1, int a2, int b1, int b2) {
            return int.min (a2, b2) - int.max (a1, b1);
        }

        ResizeLink get_link (GenericArray<ResizeLink> links, Client c) {
            for (int i = 0; i < links.length; i++) {
                if (links[i].c == c) return links[i];
            }
            var k = new ResizeLink (c, visible (c, c.geom));
            links.add (k);
            return k;
        }

        /* Borde vertical (izquierdo o derecho) de la activa. */
        void horizontal_edge (Rect av, int src, GenericArray<Client> cands, GenericArray<ResizeLink> links) {
            int e = src > 0 ? av.x + av.w : av.x;
            var near = new GenericArray<Rect?> ();
            for (int i = 0; i < cands.length; i++) {
                var cv = visible (cands[i], cands[i].geom);
                int edge = src > 0 ? cv.x : cv.x + cv.w;
                if ((edge - e).abs () <= TOLERANCE
                    && overlap (cv.y, cv.y + cv.h, av.y, av.y + av.h) >= MIN_OVERLAP) {
                    var k = get_link (links, cands[i]);
                    k.h_edge = src > 0 ? -1 : 1;
                    k.h_src = src;
                    near.add (cv);
                }
            }
            if (near.length == 0) return;
            for (int i = 0; i < cands.length; i++) {
                var cv = visible (cands[i], cands[i].geom);
                int edge = src > 0 ? cv.x + cv.w : cv.x;
                if ((edge - e).abs () > TOLERANCE) continue;
                for (int j = 0; j < near.length; j++) {
                    Rect n = near[j];
                    if (overlap (cv.y, cv.y + cv.h, n.y, n.y + n.h) >= MIN_OVERLAP) {
                        var k = get_link (links, cands[i]);
                        if (k.h_edge == 0) {
                            k.h_edge = src;
                            k.h_src = src;
                        }
                        break;
                    }
                }
            }
        }

        /* Borde horizontal (superior o inferior) de la activa. */
        void vertical_edge (Rect av, int src, GenericArray<Client> cands, GenericArray<ResizeLink> links) {
            int e = src > 0 ? av.y + av.h : av.y;
            var near = new GenericArray<Rect?> ();
            for (int i = 0; i < cands.length; i++) {
                var cv = visible (cands[i], cands[i].geom);
                int edge = src > 0 ? cv.y : cv.y + cv.h;
                if ((edge - e).abs () <= TOLERANCE
                    && overlap (cv.x, cv.x + cv.w, av.x, av.x + av.w) >= MIN_OVERLAP) {
                    var k = get_link (links, cands[i]);
                    k.v_edge = src > 0 ? -1 : 1;
                    k.v_src = src;
                    near.add (cv);
                }
            }
            if (near.length == 0) return;
            for (int i = 0; i < cands.length; i++) {
                var cv = visible (cands[i], cands[i].geom);
                int edge = src > 0 ? cv.y + cv.h : cv.y;
                if ((edge - e).abs () > TOLERANCE) continue;
                for (int j = 0; j < near.length; j++) {
                    Rect n = near[j];
                    if (overlap (cv.x, cv.x + cv.w, n.x, n.x + n.w) >= MIN_OVERLAP) {
                        var k = get_link (links, cands[i]);
                        if (k.v_edge == 0) {
                            k.v_edge = src;
                            k.v_src = src;
                        }
                        break;
                    }
                }
            }
        }

        public GenericArray<ResizeLink> find (Rect av, bool l, bool r, bool t, bool b,
                                              GenericArray<Client> cands) {
            var links = new GenericArray<ResizeLink> ();
            if (r) horizontal_edge (av, 1, cands, links);
            if (l) horizontal_edge (av, -1, cands, links);
            if (b) vertical_edge (av, 1, cands, links);
            if (t) vertical_edge (av, -1, cands, links);
            return links;
        }

        /* Limita los desplazamientos de borde para que ninguna ventana baje de su mínimo. */
        public void clamp (ref int dl, ref int dr, ref int dt, ref int db, Rect av,
                           int amin_w, int amin_h, GenericArray<ResizeLink> links) {
            if (av.w + dr - dl < amin_w) {
                if (dr != 0) dr = amin_w - av.w + dl; else dl = av.w - amin_w + dr;
            }
            if (av.h + db - dt < amin_h) {
                if (db != 0) db = amin_h - av.h + dt; else dt = av.h - amin_h + db;
            }
            for (int i = 0; i < links.length; i++) {
                var k = links[i];
                if (k.h_edge != 0) {
                    int m = min_w (k.c);
                    int d = k.h_src > 0 ? dr : dl;
                    d = k.h_edge < 0 ? int.min (d, k.start.w - m) : int.max (d, m - k.start.w);
                    if (k.h_src > 0) dr = d; else dl = d;
                }
                if (k.v_edge != 0) {
                    int m = min_h (k.c);
                    int d = k.v_src > 0 ? db : dt;
                    d = k.v_edge < 0 ? int.min (d, k.start.h - m) : int.max (d, m - k.start.h);
                    if (k.v_src > 0) db = d; else dt = d;
                }
            }
        }

        /* Rectángulo visible nuevo de una ventana enlazada. */
        public Rect moved (ResizeLink k, int dl, int dr, int dt, int db) {
            var r = k.start;
            if (k.h_edge != 0) {
                int d = k.h_src > 0 ? dr : dl;
                if (k.h_edge < 0) { r.x += d; r.w -= d; } else { r.w += d; }
            }
            if (k.v_edge != 0) {
                int d = k.v_src > 0 ? db : dt;
                if (k.v_edge < 0) { r.y += d; r.h -= d; } else { r.h += d; }
            }
            return r;
        }
    }
}
