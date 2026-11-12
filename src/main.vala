namespace Fenster {
    const string VERSION = "0.3.0-dev";

    int main (string[] args) {
        bool replace = false;
        foreach (var a in args[1:args.length]) {
            switch (a) {
            case "--replace":
                replace = true;
                break;
            case "--version":
                print ("Fenster %s\n", VERSION);
                return 0;
            case "-h":
            case "--help":
                print ("Uso: fenster [--replace] [--version]\n\n"
                       + "  --replace   sustituye al gestor de ventanas actual (p. ej. xfwm4)\n"
                       + "  --version   muestra la versión\n\n"
                       + "Depuración: G_MESSAGES_DEBUG=all fenster\n");
                return 0;
            default:
                printerr ("Opción desconocida: %s\n", a);
                return 2;
            }
        }

        try {
            var wm = new WindowManager ();
            wm.start (replace);
            wm.run ();
        } catch (Error e) {
            printerr ("fenster: %s\n", e.message);
            return 1;
        }
        return 0;
    }
}
