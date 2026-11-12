/* Configuración de usuario: ~/.config/fenster/fenster.conf
 *
 *   [General]
 *   escritorios = 4            # al arrancar sin gestor previo
 *   animaciones = true         # animación al minimizar/restaurar
 *   redimension-enlazada = true  # las ventanas pegadas cambian de tamaño juntas
 *
 *   [Regla Tilix]              # cualquier grupo "Regla …" (o "Rule …")
 *   clase = Tilix              # WM_CLASS (clase o instancia), sin mayúsculas
 *   titulo = ^Preferencias     # opcional: expresión regular sobre el título
 *   escritorio = 2             # 1…n o «todos»
 *   monitor = principal        # principal, 1, 2…
 *   tamaño = 60%x70%           # o 1200x800
 *   posicion = centro          # o 100,80
 *   estado = maximizada        # maximizada, pantalla-completa, minimizada,
 *                              # izquierda, derecha, arriba-izquierda…
 *   encima = true
 *   en-alt-tab = false
 *   enfocar = false            # no darle el foco al abrirse
 *
 * Se recarga sola al guardar el archivo (afecta a las ventanas nuevas). */
namespace Fenster {
    public class Rule {
        public string name;
        public string? klass = null;
        public Regex? title = null;
        public string? desktop = null;      /* "2" o "todos" */
        public string? monitor = null;      /* "principal" o "1" */
        public string? size = null;         /* "60%x70%" o "1200x800" */
        public string? position = null;     /* "centro" o "x,y" */
        public string? state = null;
        public int above = -1;              /* -1 sin definir, 0/1 */
        public int in_switcher = -1;
        public int take_focus = -1;

        public bool matches (string instance, string klass_name, string title_text) {
            if (klass != null) {
                var k = klass.down ();
                if (k != instance.down () && k != klass_name.down ()) {
                    return false;
                }
            }
            if (title != null && !title.match (title_text)) {
                return false;
            }
            return klass != null || title != null;
        }

        /* "60%x70%" o "1200x800" dentro de un área. */
        public bool parse_size (Rect area, out int w, out int h) {
            w = h = 0;
            if (size == null) return false;
            var parts = size.down ().replace (" ", "").split ("x");
            if (parts.length != 2) return false;
            w = dimension (parts[0], area.w);
            h = dimension (parts[1], area.h);
            return w > 0 && h > 0;
        }

        static int dimension (string s, int whole) {
            if (s.has_suffix ("%")) {
                return (int) (whole * double.parse (s.substring (0, s.length - 1)) / 100.0);
            }
            return int.parse (s);
        }

        public bool parse_position (out int x, out int y) {
            x = y = 0;
            if (position == null) return false;
            var parts = position.replace (" ", "").split (",");
            if (parts.length != 2) return false;
            x = int.parse (parts[0]);
            y = int.parse (parts[1]);
            return true;
        }

        public bool centered () {
            return position != null && (position.down () == "centro" || position.down () == "center");
        }

        public SnapZone snap_zone () {
            switch ((state ?? "").down ()) {
            case "izquierda": case "left": return SnapZone.LEFT;
            case "derecha": case "right": return SnapZone.RIGHT;
            case "arriba-izquierda": case "top-left": return SnapZone.TOP_LEFT;
            case "arriba-derecha": case "top-right": return SnapZone.TOP_RIGHT;
            case "abajo-izquierda": case "bottom-left": return SnapZone.BOTTOM_LEFT;
            case "abajo-derecha": case "bottom-right": return SnapZone.BOTTOM_RIGHT;
            case "maximizada": case "maximized": return SnapZone.MAXIMIZE;
            default: return SnapZone.NONE;
            }
        }
    }

    public class Config {
        public string path;
        public int desktops = 4;
        public bool animations = true;
        public bool linked_resize = true;
        public GenericArray<Rule> rules = new GenericArray<Rule> ();
        FileMonitor? monitor = null;

        public signal void changed ();

        public Config (string? path = null) {
            this.path = path ?? Path.build_filename (Environment.get_user_config_dir (), "fenster", "fenster.conf");
        }

        public void load () {
            desktops = 4;
            animations = true;
            linked_resize = true;
            rules = new GenericArray<Rule> ();
            var kf = new KeyFile ();
            try {
                kf.load_from_file (path, KeyFileFlags.NONE);
            } catch (FileError.NOENT e) {
                return;
            } catch (Error e) {
                warning ("No se pudo leer %s: %s", path, e.message);
                return;
            }
            try {
                if (kf.has_group ("General")) {
                    if (kf.has_key ("General", "escritorios")) {
                        desktops = int.max (1, int.min (16, kf.get_integer ("General", "escritorios")));
                    }
                    if (kf.has_key ("General", "animaciones")) {
                        animations = kf.get_boolean ("General", "animaciones");
                    }
                    if (kf.has_key ("General", "redimension-enlazada")) {
                        linked_resize = kf.get_boolean ("General", "redimension-enlazada");
                    }
                }
            } catch (Error e) {
                warning ("%s [General]: %s", path, e.message);
            }
            foreach (var group in kf.get_groups ()) {
                var g = group.down ();
                if (!g.has_prefix ("regla") && !g.has_prefix ("rule")) continue;
                try {
                    rules.add (parse_rule (kf, group));
                } catch (Error e) {
                    warning ("%s [%s]: %s", path, group, e.message);
                }
            }
            message ("Configuración cargada: %d regla(s)", rules.length);
        }

        static string? opt (KeyFile kf, string group, string key, string? alt = null) throws Error {
            if (kf.has_key (group, key)) return kf.get_string (group, key).strip ();
            if (alt != null && kf.has_key (group, alt)) return kf.get_string (group, alt).strip ();
            return null;
        }

        static int opt_bool (KeyFile kf, string group, string key) throws Error {
            if (!kf.has_key (group, key)) return -1;
            return kf.get_boolean (group, key) ? 1 : 0;
        }

        static Rule parse_rule (KeyFile kf, string group) throws Error {
            var r = new Rule ();
            r.name = group;
            r.klass = opt (kf, group, "clase", "class");
            var t = opt (kf, group, "titulo", "title");
            if (t != null) {
                r.title = new Regex (t);
            }
            r.desktop = opt (kf, group, "escritorio", "desktop");
            r.monitor = opt (kf, group, "monitor");
            r.size = opt (kf, group, "tamaño", "size");
            r.position = opt (kf, group, "posicion", "position");
            r.state = opt (kf, group, "estado", "state");
            r.above = opt_bool (kf, group, "encima");
            r.in_switcher = opt_bool (kf, group, "en-alt-tab");
            r.take_focus = opt_bool (kf, group, "enfocar");
            if (r.klass == null && r.title == null) {
                throw new KeyFileError.KEY_NOT_FOUND ("la regla necesita «clase» o «titulo»");
            }
            return r;
        }

        /* Primera regla que encaja con la ventana. */
        public Rule? match (string instance, string klass, string title) {
            for (int i = 0; i < rules.length; i++) {
                if (rules[i].matches (instance, klass, title)) {
                    return rules[i];
                }
            }
            return null;
        }

        /* Recargar al guardar el archivo. */
        public void watch () {
            try {
                monitor = File.new_for_path (path).monitor_file (FileMonitorFlags.NONE);
                monitor.changed.connect ((f, other, ev) => {
                    if (ev == FileMonitorEvent.CHANGES_DONE_HINT || ev == FileMonitorEvent.CREATED
                        || ev == FileMonitorEvent.DELETED) {
                        load ();
                        changed ();
                    }
                });
            } catch (Error e) {
                warning ("No se puede vigilar %s: %s", path, e.message);
            }
        }
    }
}
