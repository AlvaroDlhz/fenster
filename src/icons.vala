/* Iconos de aplicaciones sin GTK:
 *  1. _NET_WM_ICON de la propia ventana, si lo trae;
 *  2. si no, el .desktop que corresponde a su WM_CLASS (como hace Dock-e con
 *     Bamf) y el icono del tema según la especificación de freedesktop.
 * Sustituye a ~/.local/bin/wm-icon-fixer: Fenster asigna el icono encontrado
 * a la ventana para que el panel y demás herramientas también lo vean. */
namespace Fenster {
    [Compact]
    class IconDir {
        public string path;
        public int size;
        public bool scalable;

        public IconDir (string path, int size, bool scalable) {
            this.path = path;
            this.size = size;
            this.scalable = scalable;
        }
    }

    /* Búsqueda en temas de iconos (Icon Theme Specification). */
    public class IconFinder {
        string[] bases = {};
        string[] themes = {};
        HashTable<string, GenericArray<IconDir>> dirs = new HashTable<string, GenericArray<IconDir>> (str_hash, str_equal);
        HashTable<string, string> found = new HashTable<string, string> (str_hash, str_equal);

        public IconFinder () {
            var home = Environment.get_home_dir ();
            bases += Path.build_filename (Environment.get_user_data_dir (), "icons");
            bases += Path.build_filename (home, ".icons");
            foreach (var d in Environment.get_system_data_dirs ()) {
                bases += Path.build_filename (d, "icons");
            }
            resolve_themes (configured_theme ());
        }

        /* Tema de iconos configurado en XFCE (o GTK como alternativa). */
        static string configured_theme () {
            var home = Environment.get_home_dir ();
            try {
                string xml;
                FileUtils.get_contents (Path.build_filename (home,
                    ".config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"), out xml);
                var re = new Regex ("name=\"IconThemeName\" type=\"string\" value=\"([^\"]+)\"");
                MatchInfo m;
                if (re.match (xml, 0, out m)) {
                    return m.fetch (1);
                }
            } catch (Error e) {}
            try {
                var kf = new KeyFile ();
                kf.load_from_file (Path.build_filename (home, ".config/gtk-3.0/settings.ini"), KeyFileFlags.NONE);
                return kf.get_string ("Settings", "gtk-icon-theme-name");
            } catch (Error e) {}
            return "hicolor";
        }

        void resolve_themes (string first) {
            var queue = new GenericArray<string> ();
            queue.add (first);
            for (int i = 0; i < queue.length && i < 12; i++) {
                var t = queue[i];
                if (t in themes) continue;
                themes += t;
                foreach (var b in bases) {
                    var idx = Path.build_filename (b, t, "index.theme");
                    if (!FileUtils.test (idx, FileTest.EXISTS)) continue;
                    try {
                        var kf = new KeyFile ();
                        kf.set_list_separator (','); /* las listas de temas usan comas */
                        kf.load_from_file (idx, KeyFileFlags.NONE);
                        if (kf.has_key ("Icon Theme", "Inherits")) {
                            foreach (var parent in kf.get_string_list ("Icon Theme", "Inherits")) {
                                queue.add (parent.strip ());
                            }
                        }
                    } catch (Error e) {}
                    break;
                }
            }
            if (!("hicolor" in themes)) {
                themes += "hicolor";
            }
        }

        /* Directorios de un tema (con su tamaño). */
        unowned GenericArray<IconDir> theme_dirs (string root) {
            unowned GenericArray<IconDir>? cached = dirs[root];
            if (cached != null) {
                return cached;
            }
            var list = new GenericArray<IconDir> ();
            try {
                var kf = new KeyFile ();
                kf.set_list_separator (',');
                kf.load_from_file (Path.build_filename (root, "index.theme"), KeyFileFlags.NONE);
                string[] names = kf.get_string_list ("Icon Theme", "Directories");
                if (kf.has_key ("Icon Theme", "ScaledDirectories")) {
                    foreach (var extra in kf.get_string_list ("Icon Theme", "ScaledDirectories")) {
                        names += extra;
                    }
                }
                foreach (var d in names) {
                    /* Sin filtrar por Context: algunos temas (Mint-Y) ponen iconos
                     * de apps en otras categorías, p. ej. Thunar en «places». */
                    if (!kf.has_group (d)) continue;
                    int size = kf.has_key (d, "Size") ? kf.get_integer (d, "Size") : 48;
                    int scale = kf.has_key (d, "Scale") ? kf.get_integer (d, "Scale") : 1;
                    string type = kf.has_key (d, "Type") ? kf.get_string (d, "Type") : "Threshold";
                    list.add (new IconDir (d, size * scale, type == "Scalable"));
                }
            } catch (Error e) {}
            dirs[root] = list;
            return dirs[root];
        }

        /* Ruta del mejor fichero para «name» a un tamaño dado, o null. */
        public string? find (string name, int size) {
            if (Path.is_absolute (name)) {
                return FileUtils.test (name, FileTest.EXISTS) ? name : null;
            }
            var key = "%s@%d".printf (name, size);
            unowned string? hit = found[key];
            if (hit != null) {
                return hit == "" ? null : hit;
            }
            string? result = null;
            foreach (var theme in themes) {
                int best_score = int.MAX;
                foreach (var b in bases) {
                    var root = Path.build_filename (b, theme);
                    if (!FileUtils.test (root, FileTest.IS_DIR)) continue;
                    unowned var list = theme_dirs (root);
                    for (int i = 0; i < list.length; i++) {
                        unowned IconDir d = list[i];
                        foreach (var ext in new string[] { "svg", "png" }) {
                            var p = Path.build_filename (root, d.path, name + "." + ext);
                            if (!FileUtils.test (p, FileTest.EXISTS)) continue;
                            int score = d.scalable ? 0
                                      : d.size >= size ? d.size - size
                                      : 1000 + size - d.size;
                            if (score < best_score) {
                                best_score = score;
                                result = p;
                            }
                        }
                    }
                }
                if (result != null) break;
            }
            if (result == null) {
                foreach (var ext in new string[] { "svg", "png", "xpm" }) {
                    var p = "/usr/share/pixmaps/%s.%s".printf (name, ext);
                    if (FileUtils.test (p, FileTest.EXISTS)) {
                        result = p;
                        break;
                    }
                }
            }
            found[key] = result ?? "";
            return result;
        }
    }

    /* WM_CLASS → icono, a partir de los .desktop instalados. */
    public class AppIndex {
        HashTable<string, Icon> index = new HashTable<string, Icon> (str_hash, str_equal);
        int64 built_at = 0;

        public void rebuild () {
            index.remove_all ();
            foreach (var app in AppInfo.get_all ()) {
                var dai = app as DesktopAppInfo;
                if (dai == null || dai.get_icon () == null) continue;
                var icon = dai.get_icon ();
                string[] keys = {};
                var wm = dai.get_startup_wm_class ();
                if (wm != null) keys += wm;
                var id = dai.get_id () ?? "";
                if (id.has_suffix (".desktop")) {
                    id = id.substring (0, id.length - 8);
                }
                if (id != "") {
                    keys += id;
                    var parts = id.split (".");
                    keys += parts[parts.length - 1];
                }
                var exe = dai.get_executable ();
                if (exe != null) keys += Path.get_basename (exe);
                var cmd = dai.get_commandline () ?? "";
                MatchInfo m;
                try {
                    if (new Regex ("--command=(\\S+)").match (cmd, 0, out m)) {
                        keys += Path.get_basename (m.fetch (1));
                    }
                } catch (Error e) {}
                foreach (var k in keys) {
                    var lk = k.down ();
                    if (!index.contains (lk)) {
                        index[lk] = icon;
                    }
                }
            }
            built_at = get_monotonic_time ();
        }

        public Icon? lookup (string instance, string klass) {
            if (built_at == 0) {
                rebuild ();
            }
            var hit = index[instance.down ()] ?? index[klass.down ()];
            /* App instalada después de construir el índice: reintentar (máx. cada 30 s) */
            if (hit == null && get_monotonic_time () - built_at > 30 * 1000000) {
                rebuild ();
                hit = index[instance.down ()] ?? index[klass.down ()];
            }
            return hit;
        }
    }

    /* Carga y conversión de iconos a superficies cairo. */
    public class Icons {
        public const int SIZE = 64;
        IconFinder finder = new IconFinder ();
        AppIndex apps = new AppIndex ();

        /* Elige del _NET_WM_ICON la imagen más pequeña ≥ size (o la mayor). */
        public static Cairo.ImageSurface? from_net_wm_icon (long[] d, int size) {
            int best = -1, best_w = 0, best_h = 0;
            int i = 0;
            while (i + 2 <= d.length) {
                int w = (int) d[i], h = (int) d[i + 1];
                if (w <= 0 || h <= 0 || i + 2 + (long) w * h > d.length) break;
                bool better = best < 0
                    || (w >= size && (best_w < size || w < best_w))
                    || (best_w < size && w > best_w);
                if (better) {
                    best = i; best_w = w; best_h = h;
                }
                i += 2 + w * h;
            }
            if (best < 0) {
                return null;
            }
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, best_w, best_h);
            surf.flush ();
            uchar* base_ptr = surf.get_data ();
            int stride = surf.get_stride ();
            for (int y = 0; y < best_h; y++) {
                uint32* row = (uint32*) (base_ptr + y * stride);
                for (int x = 0; x < best_w; x++) {
                    uint32 argb = (uint32) d[best + 2 + y * best_w + x];
                    row[x] = premultiply (argb);
                }
            }
            surf.mark_dirty ();
            return surf;
        }

        static uint32 premultiply (uint32 argb) {
            uint32 a = argb >> 24;
            if (a == 255) return argb;
            uint32 r = ((argb >> 16) & 0xff) * a / 255;
            uint32 g = ((argb >> 8) & 0xff) * a / 255;
            uint32 b = (argb & 0xff) * a / 255;
            return (a << 24) | (r << 16) | (g << 8) | b;
        }

        static Cairo.ImageSurface from_pixbuf (Gdk.Pixbuf pb) {
            int w = pb.width, h = pb.height, n = pb.n_channels, rs = pb.rowstride;
            unowned uint8[] px = pb.get_pixels_with_length ();
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            surf.flush ();
            uchar* base_ptr = surf.get_data ();
            int stride = surf.get_stride ();
            for (int y = 0; y < h; y++) {
                uint32* row = (uint32*) (base_ptr + y * stride);
                for (int x = 0; x < w; x++) {
                    int o = y * rs + x * n;
                    uint32 a = n == 4 ? px[o + 3] : 255;
                    row[x] = premultiply ((a << 24) | ((uint32) px[o] << 16)
                                          | ((uint32) px[o + 1] << 8) | px[o + 2]);
                }
            }
            surf.mark_dirty ();
            return surf;
        }

        /* Icono del tema para una ventana, buscando su app por WM_CLASS. */
        public Cairo.ImageSurface? from_theme (string instance, string klass) {
            var gicon = apps.lookup (instance, klass);
            string? path = null;
            if (gicon is ThemedIcon) {
                foreach (var name in ((ThemedIcon) gicon).get_names ()) {
                    path = finder.find (name, SIZE);
                    if (path != null) break;
                }
            } else if (gicon is FileIcon) {
                path = ((FileIcon) gicon).get_file ().get_path ();
            }
            if (path == null) {
                /* Último intento: un icono con el nombre de la clase */
                path = finder.find (klass.down (), SIZE) ?? finder.find (instance.down (), SIZE);
            }
            debug ("icono para %s/%s: %s → %s", instance, klass,
                   gicon != null ? gicon.to_string () : "(sin .desktop)", path ?? "(no encontrado)");
            if (path == null) {
                return null;
            }
            try {
                return from_pixbuf (new Gdk.Pixbuf.from_file_at_size (path, SIZE, SIZE));
            } catch (Error e) {
                debug ("no se pudo cargar %s: %s", path, e.message);
                return null;
            }
        }

        /* Superficie → datos de _NET_WM_ICON (ARGB sin premultiplicar). */
        public static long[] to_net_wm_icon (Cairo.ImageSurface surf) {
            int w = surf.get_width (), h = surf.get_height ();
            long[] d = new long[2 + w * h];
            d[0] = w;
            d[1] = h;
            surf.flush ();
            uchar* base_ptr = surf.get_data ();
            int stride = surf.get_stride ();
            for (int y = 0; y < h; y++) {
                uint32* row = (uint32*) (base_ptr + y * stride);
                for (int x = 0; x < w; x++) {
                    uint32 p = row[x];
                    uint32 a = p >> 24;
                    uint32 r = (p >> 16) & 0xff, g = (p >> 8) & 0xff, b = p & 0xff;
                    if (a > 0 && a < 255) {
                        r = uint32.min (255, r * 255 / a);
                        g = uint32.min (255, g * 255 / a);
                        b = uint32.min (255, b * 255 / a);
                    }
                    d[2 + y * w + x] = (long) ((a << 24) | (r << 16) | (g << 8) | b);
                }
            }
            return d;
        }
    }
}
