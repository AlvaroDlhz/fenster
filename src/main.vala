namespace Fenster {
    const string VERSION = "0.3.0-dev";

    int main (string[] args) {
        bool replace = false;
        string? config_path = null;
        for (int i = 1; i < args.length; i++) {
            var a = args[i];
            switch (a) {
            case "--replace":
                replace = true;
                break;
            case "--config":
                if (i + 1 >= args.length) {
                    printerr ("--config necesita una ruta\n");
                    return 2;
                }
                config_path = args[++i];
                break;
            case "--version":
                print ("Fenster %s\n", VERSION);
                return 0;
            case "-h":
            case "--help":
                print ("Uso: fenster [--replace] [--config RUTA] [--version]\n\n"
                       + "  --replace       sustituye al gestor de ventanas actual (p. ej. xfwm4)\n"
                       + "  --config RUTA   archivo de configuración (por defecto\n"
                       + "                  ~/.config/fenster/fenster.conf)\n"
                       + "  --version       muestra la versión\n\n"
                       + "Depuración: G_MESSAGES_DEBUG=all fenster\n");
                return 0;
            default:
                printerr ("Opción desconocida: %s\n", a);
                return 2;
            }
        }

        try {
            var wm = new WindowManager (config_path);
            wm.start (replace);
            wm.run ();
        } catch (Error e) {
            printerr ("fenster: %s\n", e.message);
            return 1;
        }
        return 0;
    }
}
