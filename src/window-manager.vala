namespace Fenster {
    enum DragMode { NONE, MOVE, RESIZE }

    /* EWMH _NET_WM_MOVERESIZE direcciones */
    const int DIR_TOPLEFT = 0;
    const int DIR_TOP = 1;
    const int DIR_TOPRIGHT = 2;
    const int DIR_RIGHT = 3;
    const int DIR_BOTTOMRIGHT = 4;
    const int DIR_BOTTOM = 5;
    const int DIR_BOTTOMLEFT = 6;
    const int DIR_LEFT = 7;
    const int DIR_MOVE = 8;
    const int DIR_CANCEL = 11;

    const int MIN_SIZE = 64;
    const uint MAX_DESKTOPS = 16;

    public class WindowManager {
        X.Display dpy;
        X.Window root;
        int screen;
        int screen_w;
        int screen_h;
        Atoms atoms;
        X.Window check_win;
        MainLoop loop;

        GenericArray<Client> clients = new GenericArray<Client> ();   /* orden de mapeo */
        GenericArray<Client> stacking = new GenericArray<Client> ();  /* abajo → arriba */
        GenericArray<Client> mru = new GenericArray<Client> ();       /* más reciente primero */
        Client? focused = null;
        Rect workarea;          /* _NET_WORKAREA global (compatibilidad) */
        Monitors monitors;
        int rr_event_base = -1;
        int damage_event_base = -1;

        /* Escritorios virtuales */
        uint n_desktops = 4;
        uint current_desktop = 0;

        /* Arrastre (Alt+ratón o _NET_WM_MOVERESIZE) */
        DragMode drag = DragMode.NONE;
        Client? drag_client = null;
        int drag_dir = DIR_MOVE;
        int drag_px;
        int drag_py;
        Rect drag_start;
        GenericArray<ResizeLink> links = new GenericArray<ResizeLink> ();

        /* Alt+Tab (una entrada por aplicación, como macOS) */
        bool cycling = false;
        GenericArray<SwitcherItem> sw_items = new GenericArray<SwitcherItem> ();
        int cycle_index = 0;
        uint sw_timer = 0;
        Switcher switcher;
        SnapPreview preview;
        SnapZone drag_zone = SnapZone.NONE;
        Monitor? drag_zone_mon = null;
        Icons icons = new Icons ();

        static uchar last_error = 0;

        static int on_x_error (X.Display d, X.ErrorEvent* e) {
            last_error = e->error_code;
            return 0;
        }

        /* ---------------------------------------------------------------- */
        /* Arranque                                                          */
        /* ---------------------------------------------------------------- */

        Config config;

        public WindowManager (string? config_path = null) throws Error {
            config = new Config (config_path);
            config.load ();
            dpy = new X.Display (null);
            if (dpy == null) {
                throw new IOError.FAILED ("No se pudo abrir el display X11 (¿está definida $DISPLAY?)");
            }
            screen = Xx.default_screen (dpy);
            root = dpy.default_root_window ();
            read_root_size ();
            atoms = new Atoms (dpy);
            workarea = Rect (0, 0, screen_w, screen_h);
            Xx.set_error_handler (on_x_error);
            int rr_err;
            bool randr = Xrr.query_extension (dpy, out rr_event_base, out rr_err);
            if (!randr) {
                rr_event_base = -1;
                warning ("RandR no disponible: se usará un solo monitor");
            }
            monitors = new Monitors (randr);
            int dmg_err;
            if (!Xd.query_extension (dpy, out damage_event_base, out dmg_err)) {
                damage_event_base = -1;
            }
        }

        public void start (bool replace) throws Error {
            check_win = Xx.create_simple_window (dpy, root, -10, -10, 1, 1, 0, 0, 0);
            acquire_wm_selection (replace);

            last_error = 0;
            dpy.select_input (root, (long) (Xc.SUBSTRUCTURE_REDIRECT_MASK
                                            | Xc.SUBSTRUCTURE_NOTIFY_MASK
                                            | Xc.PROPERTY_CHANGE_MASK
                                            | Xc.BUTTON_PRESS_MASK));
            Xx.sync (dpy, false);
            if (last_error == Xc.BAD_ACCESS) {
                throw new IOError.EXISTS ("Ya hay otro gestor de ventanas activo. Usa --replace.");
            }

            Xx.define_cursor (dpy, root, Xx.create_font_cursor (dpy, Xc.XC_LEFT_PTR));
            if (rr_event_base >= 0) {
                Xrr.select_input (dpy, root, Xrr.SCREEN_CHANGE_NOTIFY_MASK);
            }
            monitors.refresh (dpy, root, screen_w, screen_h);
            n_desktops = config.desktops;
            config.watch ();
            /* Heredar escritorios y ventana activa del gestor anterior (p. ej. xfwm4) */
            var nd = get_longs (root, atoms.net_number_of_desktops, Xc.XA_CARDINAL, 1);
            if (nd.length > 0 && nd[0] >= 1 && nd[0] <= MAX_DESKTOPS) {
                n_desktops = (uint) nd[0];
            }
            var cd = get_longs (root, atoms.net_current_desktop, Xc.XA_CARDINAL, 1);
            if (cd.length > 0 && cd[0] >= 0 && cd[0] < n_desktops) {
                current_desktop = (uint) cd[0];
            }
            var prev_active = get_longs (root, atoms.net_active_window, Xc.XA_WINDOW, 1);
            setup_ewmh ();
            switcher = new Switcher (dpy, root, screen, atoms);
            preview = new SnapPreview (dpy, root, screen, atoms);
            grab_keys ();
            scan_existing ();
            update_workarea ();
            update_client_lists ();
            Client? was_active = prev_active.length > 0 ? find ((X.Window) prev_active[0]) : null;
            if (was_active != null && was_active.can_focus ()) {
                focus (was_active);
                raise (was_active);
            } else if (focused == null) {
                focus_next ();
            }
            message ("Fenster activo: pantalla %dx%d, %s", screen_w, screen_h, describe_monitors ());
        }

        void acquire_wm_selection (bool replace) throws Error {
            var sel = dpy.intern_atom ("WM_S%d".printf (screen), false);
            var owner = dpy.get_selection_owner (sel);
            if (owner != 0 && !replace) {
                throw new IOError.EXISTS ("Ya hay otro gestor de ventanas activo. Usa --replace.");
            }
            dpy.set_selection_owner (sel, check_win, Xc.CURRENT_TIME);
            if (owner == 0) {
                return;
            }
            /* Esperar a que el gestor anterior suelte la pantalla (máx. 5 s). */
            for (int i = 0; i < 100; i++) {
                last_error = 0;
                X.WindowAttributes attrs;
                dpy.get_window_attributes (owner, out attrs);
                Xx.sync (dpy, false);
                if (last_error != 0) {
                    return;
                }
                Thread.usleep (50000);
            }
            warning ("El gestor anterior no salió a tiempo; continúo igualmente");
        }

        void setup_ewmh () {
            long[] check = { (long) check_win };
            set_prop (root, atoms.net_supporting_wm_check, Xc.XA_WINDOW, check);
            set_prop (check_win, atoms.net_supporting_wm_check, Xc.XA_WINDOW, check);
            var name = "Fenster";
            Xx.change_property (dpy, check_win, atoms.net_wm_name, atoms.utf8_string, 8,
                                Xc.PROP_MODE_REPLACE, (void*) name.data, name.length);

            var sup = atoms.supported ();
            long[] sup_l = new long[sup.length];
            for (int i = 0; i < sup.length; i++) {
                sup_l[i] = (long) sup[i];
            }
            set_prop (root, atoms.net_supported, Xc.XA_ATOM, sup_l);
            update_desktop_props ();
        }

        void scan_existing () {
            X.Window r, p;
            X.Window[] children;
            dpy.query_tree (root, out r, out p, out children);
            foreach (var w in children) {
                if (w == check_win) {
                    continue;
                }
                X.WindowAttributes a;
                last_error = 0;
                dpy.get_window_attributes (w, out a);
                if (last_error != 0 || a.override_redirect) {
                    continue;
                }
                var st = get_longs (w, atoms.wm_state, atoms.wm_state, 2);
                bool iconic = st.length > 0 && st[0] == Xc.ICONIC_STATE;
                bool had_state = st.length > 0 && st[0] != Xc.WITHDRAWN_STATE;
                if (a.map_state == 2 /* IsViewable */ || had_state) {
                    manage (w, iconic, true);
                }
            }
        }

        public void run () {
            loop = new MainLoop ();
            var ch = new IOChannel.unix_new (dpy.connection_number ());
            ch.add_watch (IOCondition.IN, () => {
                process_events ();
                return Source.CONTINUE;
            });
            Unix.signal_add (2, () => { loop.quit (); return Source.REMOVE; });
            Unix.signal_add (15, () => { loop.quit (); return Source.REMOVE; });
            process_events ();
            loop.run ();
            shutdown ();
        }

        void shutdown () {
            /* No dejar ventanas minimizadas "perdidas" para el siguiente gestor. */
            clients.foreach ((c) => {
                if (c.minimized || c.hidden_by_desktop) {
                    dpy.map_window (c.win);
                    set_wm_state (c, Xc.NORMAL_STATE);
                }
            });
            dpy.delete_property (root, atoms.net_supporting_wm_check);
            Xx.sync (dpy, false);
            message ("Fenster terminado");
        }

        void process_events () {
            while (dpy.pending () > 0) {
                var ev = X.Event ();
                dpy.next_event (ref ev);
                handle_event (ref ev);
            }
        }

        /* ---------------------------------------------------------------- */
        /* Eventos                                                           */
        /* ---------------------------------------------------------------- */

        void handle_event (ref X.Event ev) {
            if (damage_event_base >= 0 && ev.type == damage_event_base + Xd.NOTIFY) {
                on_painted (ev.xany.window);  /* XDamageNotifyEvent.drawable */
                return;
            }
            if (rr_event_base >= 0 && ev.type == rr_event_base + Xrr.SCREEN_CHANGE_NOTIFY) {
                Xrr.update_configuration (&ev);
                on_screen_change ();
                return;
            }
            switch (ev.type) {
            case Xc.MAP_REQUEST:
                manage (ev.xmaprequest.window, false, false);
                break;
            case Xc.CONFIGURE_REQUEST:
                on_configure_request (ref ev.xconfigurerequest);
                break;
            case Xc.UNMAP_NOTIFY:
                on_unmap (ev.xunmap.window, ev.xunmap.send_event);
                break;
            case Xc.DESTROY_NOTIFY:
                var c = find (ev.xdestroywindow.window);
                if (c != null) {
                    unmanage (c, true);
                }
                break;
            case Xc.BUTTON_PRESS:
                on_button_press (ref ev.xbutton);
                break;
            case Xc.MOTION_NOTIFY:
                on_motion (ev.xmotion.x_root, ev.xmotion.y_root);
                break;
            case Xc.BUTTON_RELEASE:
                on_button_release (ev.xbutton.x_root, ev.xbutton.y_root);
                break;
            case Xc.KEY_PRESS:
                on_key_press (ref ev.xkey);
                break;
            case 3: /* KeyRelease */
                on_key_release (ref ev.xkey);
                break;
            case Xc.CLIENT_MESSAGE:
                on_client_message (ref ev.xclient);
                break;
            case Xc.PROPERTY_NOTIFY:
                on_property (ev.xproperty.window, ev.xproperty.atom);
                break;
            case 29: /* SelectionClear: otro gestor pidió --replace */
                message ("Otro gestor de ventanas toma el control; Fenster sale");
                loop.quit ();
                break;
            case 12: /* Expose */
                if (switcher != null && ev.xany.window == switcher.window) {
                    switcher.draw ();
                } else if (preview != null && ev.xany.window == preview.window) {
                    preview.draw ();
                }
                break;
            case Xc.MAPPING_NOTIFY:
                Xx.refresh_keyboard_mapping (&ev);
                grab_keys ();
                break;
            }
        }

        void on_configure_request (ref X.ConfigureRequestEvent e) {
            var c = find (e.window);
            if (c != null && !c.kind.is_chrome ()) {
                if (c.fullscreen || c.maximized || c.snapped) {
                    /* Mantener la geometría impuesta; solo confirmar. */
                    apply_geometry (c, c.geom);
                    return;
                }
                var g = c.geom;
                if ((e.value_mask & Xc.CW_X) != 0) g.x = e.x;
                if ((e.value_mask & Xc.CW_Y) != 0) g.y = e.y;
                if ((e.value_mask & Xc.CW_WIDTH) != 0) g.w = e.width;
                if ((e.value_mask & Xc.CW_HEIGHT) != 0) g.h = e.height;
                c.hints.constrain (ref g.w, ref g.h, false);
                apply_geometry (c, g);
                return;
            }
            var wc = X.WindowChanges ();
            wc.x = e.x;
            wc.y = e.y;
            wc.width = e.width;
            wc.height = e.height;
            wc.border_width = 0;
            wc.sibling = e.above;
            wc.stack_mode = e.detail;
            dpy.configure_window (e.window, (uint) e.value_mask, wc);
            if (c != null) {
                c.geom = read_geometry (c.win);
                if (c.kind == ClientKind.DOCK) {
                    update_workarea ();
                }
            }
        }

        void on_unmap (X.Window w, bool synthetic) {
            var c = find (w);
            if (c == null) {
                return;
            }
            if (c.ignore_unmaps > 0 && !synthetic) {
                c.ignore_unmaps--;
                return;
            }
            unmanage (c, false);
        }

        void on_property (X.Window w, X.Atom a) {
            var c = find (w);
            if (c == null) {
                /* GTK guarda _NET_WM_USER_TIME en una ventana auxiliar */
                if (a == atoms.net_wm_user_time) {
                    for (int i = 0; i < clients.length; i++) {
                        if (clients[i].user_time_win == w) {
                            read_user_time (clients[i]);
                        }
                    }
                }
                return;
            }
            if (a == atoms.net_wm_strut_partial || a == atoms.net_wm_strut) {
                read_struts (c);
                update_workarea ();
            } else if (a == atoms.gtk_frame_extents) {
                read_csd (c);
            } else if (a == atoms.wm_normal_hints) {
                c.hints = SizeHints.parse (get_longs (w, atoms.wm_normal_hints, (X.Atom) 41, 18));
            } else if (a == atoms.wm_hints) {
                var h = WmHints.parse (get_longs (w, atoms.wm_hints, atoms.wm_hints, 9));
                c.accepts_input = h.accepts_input;
                if (h.urgent != c.urgent && !(h.urgent && c == focused)) {
                    set_urgent (c, h.urgent);
                }
            } else if (a == atoms.net_wm_user_time) {
                read_user_time (c);
            } else if (a == atoms.net_wm_icon) {
                c.icon_loaded = false;
                c.icon = null;
            }
        }

        void on_client_message (ref X.ClientMessageEvent e) {
            var type = e.message_type;

            if (type == atoms.net_request_frame_extents) {
                set_prop (e.window, atoms.net_frame_extents, Xc.XA_CARDINAL, { 0, 0, 0, 0 });
                return;
            }

            /* Mensajes a la raíz (paginadores, panel) */
            if (type == atoms.net_current_desktop) {
                switch_desktop ((uint) e.l[0]);
                return;
            }
            if (type == atoms.net_number_of_desktops) {
                set_desktop_count ((uint) e.l[0]);
                return;
            }

            var c = find (e.window);
            if (c == null) {
                return;
            }

            if (type == atoms.net_active_window) {
                /* Fuente 1 = la propia app: puede ser un robo de foco.
                 * Fuente 2 = paginador/dock (Dock-e): siempre se obedece. */
                long source = e.l[0];
                if (source == 1 && !allow_activation (c, (ulong) e.l[1])) {
                    set_urgent (c, true);
                } else {
                    activate (c);
                }
            } else if (type == atoms.net_wm_desktop) {
                move_to_desktop (c, (uint) e.l[0], false);
            } else if (type == atoms.net_close_window) {
                close (c);
            } else if (type == atoms.wm_change_state) {
                if (e.l[0] == Xc.ICONIC_STATE) {
                    minimize (c);
                }
            } else if (type == atoms.net_wm_state) {
                int action = (int) e.l[0]; /* 0 quitar, 1 añadir, 2 alternar */
                for (int i = 1; i <= 2; i++) {
                    var prop = (X.Atom) e.l[i];
                    if (prop == 0) {
                        continue;
                    }
                    if (prop == atoms.net_wm_state_fullscreen) {
                        set_fullscreen (c, want (action, c.fullscreen));
                    } else if (prop == atoms.net_wm_state_maximized_vert
                               || prop == atoms.net_wm_state_maximized_horz) {
                        set_maximized (c, want (action, c.maximized));
                        break; /* vert y horz llegan juntos: una sola vez */
                    } else if (prop == atoms.net_wm_state_hidden) {
                        if (want (action, c.minimized)) minimize (c); else activate (c);
                    } else if (prop == atoms.net_wm_state_above) {
                        set_above (c, want (action, c.above));
                    } else if (prop == atoms.net_wm_state_below) {
                        c.below = want (action, c.below);
                        if (c.below) c.above = false;
                        restack ();
                        update_net_wm_state (c);
                    } else if (prop == atoms.net_wm_state_sticky) {
                        move_to_desktop (c, want (action, c.sticky ()) ? ALL_DESKTOPS : current_desktop, false);
                    } else if (prop == atoms.net_wm_state_skip_taskbar) {
                        c.skip_taskbar = want (action, c.skip_taskbar);
                        update_net_wm_state (c);
                    } else if (prop == atoms.net_wm_state_skip_pager) {
                        c.skip_pager = want (action, c.skip_pager);
                        update_net_wm_state (c);
                    } else if (prop == atoms.net_wm_state_modal) {
                        c.modal = want (action, c.modal);
                        update_net_wm_state (c);
                    } else if (prop == atoms.net_wm_state_demands_attention) {
                        set_urgent (c, want (action, c.urgent));
                    }
                }
            } else if (type == atoms.net_wm_moveresize) {
                int dir = (int) e.l[2];
                if (dir == DIR_CANCEL) {
                    end_drag ();
                } else if (dir >= DIR_TOPLEFT && dir <= DIR_MOVE) {
                    begin_drag (c, dir == DIR_MOVE ? DragMode.MOVE : DragMode.RESIZE,
                                dir, (int) e.l[0], (int) e.l[1]);
                }
            }
        }

        static bool want (int action, bool current) {
            return action == 2 ? !current : action == 1;
        }

        /* ---------------------------------------------------------------- */
        /* Gestión de ventanas                                               */
        /* ---------------------------------------------------------------- */

        void manage (X.Window w, bool start_minimized, bool existing) {
            if (find (w) != null) {
                return;
            }
            X.WindowAttributes a;
            last_error = 0;
            dpy.get_window_attributes (w, out a);
            if (last_error != 0 || a.override_redirect) {
                if (last_error == 0) {
                    dpy.map_window (w);
                }
                return;
            }

            var c = new Client (w);
            c.geom = Rect (a.x, a.y, a.width, a.height);
            c.kind = read_kind (w);
            X.Window t;
            if (dpy.get_transient_for_hint (w, out t) != 0 && t != 0 && t != root) {
                c.transient_for = t;
                if (c.kind == ClientKind.NORMAL) {
                    c.kind = ClientKind.DIALOG;
                }
            }
            foreach (var p in get_longs (w, atoms.wm_protocols, Xc.XA_ATOM, 32)) {
                if ((X.Atom) p == atoms.wm_delete_window) c.supports_delete = true;
                if ((X.Atom) p == atoms.wm_take_focus) c.supports_take_focus = true;
            }
            read_struts (c);
            read_csd (c);
            c.hints = SizeHints.parse (get_longs (w, atoms.wm_normal_hints, (X.Atom) 41, 18));
            read_wm_class (c);
            Rule? rule = c.kind.is_chrome () ? null : config.match (c.wm_instance, c.wm_class, read_title (w));
            if (rule != null) {
                debug ("regla «%s» para %s", rule.name, c.wm_class);
                if (rule.above == 1) c.above = true;
                if (rule.in_switcher == 0) c.skip_taskbar = true;
            }
            var wmh = WmHints.parse (get_longs (w, atoms.wm_hints, atoms.wm_hints, 9));
            c.accepts_input = wmh.accepts_input;
            c.urgent = wmh.urgent;
            read_user_time_window (c);
            read_user_time (c);

            /* Estado pedido antes de mapear (pantalla completa, capas, etc.) */
            bool want_fs = false, want_max = false, want_hidden = false, want_sticky = false;
            var net_state = get_longs (w, atoms.net_wm_state, Xc.XA_ATOM, 32);
            foreach (var s in net_state) {
                var at = (X.Atom) s;
                if (at == atoms.net_wm_state_fullscreen) want_fs = true;
                else if (at == atoms.net_wm_state_maximized_vert) want_max = true;
                else if (at == atoms.net_wm_state_hidden) want_hidden = true;
                else if (at == atoms.net_wm_state_sticky) want_sticky = true;
                else if (at == atoms.net_wm_state_above) c.above = true;
                else if (at == atoms.net_wm_state_below) c.below = true;
                else if (at == atoms.net_wm_state_skip_taskbar) c.skip_taskbar = true;
                else if (at == atoms.net_wm_state_skip_pager) c.skip_pager = true;
                else if (at == atoms.net_wm_state_modal) c.modal = true;
                else if (at == atoms.net_wm_state_demands_attention) c.urgent = true;
            }

            /* Escritorio: chrome en todos; diálogos con su madre; si no, el pedido o el actual */
            Client? parent = c.transient_for != 0 ? find (c.transient_for) : null;
            if (c.kind.is_chrome () || want_sticky) {
                c.desktop = ALL_DESKTOPS;
            } else if (parent != null) {
                c.desktop = parent.desktop;
            } else if (rule != null && rule.desktop != null && !existing) {
                var rd = rule.desktop.down ();
                uint req = (rd == "todos" || rd == "all") ? ALL_DESKTOPS : (uint) (int.parse (rd) - 1);
                c.desktop = (req < n_desktops || req == ALL_DESKTOPS) ? req : current_desktop;
            } else {
                var d = get_longs (w, atoms.net_wm_desktop, Xc.XA_CARDINAL, 1);
                uint req = d.length > 0 ? (uint) d[0] : current_desktop;
                c.desktop = (req < n_desktops || req == ALL_DESKTOPS) ? req : current_desktop;
            }

            /* Minimizada al empezar: ICCCM initial_state para ventanas nuevas;
             * para las heredadas, solo si EWMH dice HIDDEN (xfwm4 también marca
             * Iconic las ventanas de otros escritorios). */
            bool iconic = existing
                ? start_minimized && (want_hidden || net_state.length == 0)
                : (wmh.start_iconic || want_hidden);
            string rule_state = rule != null && !existing ? (rule.state ?? "").down () : "";
            if (rule_state == "minimizada" || rule_state == "minimized") {
                iconic = true;
            }

            Monitor? rule_mon = null;
            if (!c.kind.is_chrome ()) {
                c.geom = place (c);
                if (rule != null && !existing) {
                    rule_mon = apply_rule_geometry (c, rule);
                }
            }

            dpy.select_input (w, (long) Xc.PROPERTY_CHANGE_MASK);
            var wc = X.WindowChanges ();
            wc.border_width = 0;
            dpy.configure_window (w, (uint) Xc.CW_BORDER_WIDTH, wc);
            if (!c.kind.is_chrome ()) {
                dpy.move_resize_window (w, c.geom.x, c.geom.y, c.geom.w, c.geom.h);
            }
            set_prop (w, atoms.net_frame_extents, Xc.XA_CARDINAL, { 0, 0, 0, 0 });
            set_prop (w, atoms.net_wm_desktop, Xc.XA_CARDINAL, { (long) c.desktop });

            clients.add (c);
            stacking.add (c);
            if (!c.kind.is_chrome ()) {
                mru.add (c);
                grab_buttons (c, false);
            }

            bool viewable = a.map_state == 2;
            if (iconic) {
                c.minimized = true;
                c.hidden_by_desktop = !c.on_desktop (current_desktop);
                if (viewable) {
                    c.ignore_unmaps++;
                    dpy.unmap_window (w);
                }
                set_wm_state (c, Xc.ICONIC_STATE);
            } else if (!c.on_desktop (current_desktop)) {
                c.hidden_by_desktop = true;
                if (viewable) {
                    c.ignore_unmaps++;
                    dpy.unmap_window (w);
                }
                set_wm_state (c, Xc.NORMAL_STATE);
            } else {
                dpy.map_window (w);
                set_wm_state (c, Xc.NORMAL_STATE);
                var rule_zone = rule != null && !existing ? rule.snap_zone () : SnapZone.NONE;
                if (want_fs || rule_state == "pantalla-completa" || rule_state == "fullscreen") {
                    set_fullscreen (c, true);
                } else if (rule_zone != SnapZone.NONE) {
                    snap (c, rule_zone, rule_mon ?? monitor_of (c));
                } else if (want_max) {
                    set_maximized (c, true);
                }
            }
            update_net_wm_state (c);

            if (c.kind == ClientKind.DOCK) {
                update_workarea ();
            }

            if (!c.kind.is_chrome ()) {
                ensure_icon (c);
            }

            /* Foco: las ventanas heredadas no lo toman; las nuevas solo si no lo roban. */
            bool rule_no_focus = rule != null && rule.take_focus == 0;
            bool take_focus = !existing && c.can_focus () && !rule_no_focus && should_focus_new (c);
            if (!take_focus && !existing && c.can_focus () && focused != null) {
                /* Queda justo debajo de la ventana activa y pide atención */
                stacking.remove (c);
                int idx = 0;
                for (int i = 0; i < stacking.length; i++) {
                    if (stacking[i] == focused) idx = i;
                }
                stacking.insert (idx, c);
                if (!rule_no_focus) {
                    set_urgent (c, true);  /* robo de foco evitado: pedir atención */
                }
            }
            restack ();
            update_client_lists ();
            if (take_focus) {
                focus (c);
            }
            debug ("gestionada 0x%lx (%s, escritorio %u%s)", (ulong) w, c.kind.to_string (),
                   c.desktop, take_focus ? ", con foco" : "");
        }

        void unmanage (Client c, bool destroyed) {
            if (drag_client == c) {
                end_drag ();
            }
            if (cycling) {
                for (int i = 0; i < sw_items.length; i++) {
                    if (sw_items[i].top == c) {
                        end_cycle (false);
                        break;
                    }
                }
            }
            clients.remove (c);
            stacking.remove (c);
            mru.remove (c);
            if (c.anim != null) {
                c.anim.finish ();
                c.anim = null;
            }
            if (c.paint_damage != 0 && !destroyed) {
                Xd.destroy (dpy, c.paint_damage);
            }
            c.paint_damage = 0;
            uint t = anim_timers[c];
            if (t != 0) {
                Source.remove (t);
                anim_timers.remove (c);
            }
            if (!destroyed) {
                set_wm_state (c, Xc.WITHDRAWN_STATE);
                dpy.ungrab_button (Xc.ANY_BUTTON, Xc.ANY_MODIFIER, c.win);
            }
            if (c.kind == ClientKind.DOCK) {
                update_workarea ();
            }
            update_client_lists ();
            if (focused == c) {
                focused = null;
                focus_next ();
            }
        }

        Rect place (Client c) {
            var g = c.geom;
            Client? parent = c.transient_for != 0 ? find (c.transient_for) : null;
            /* Sin USPosition/PPosition la posición es arbitraria: colocamos nosotros */
            bool unplaced = !c.hints.user_position || (g.x == 0 && g.y == 0);
            c.hints.constrain (ref g.w, ref g.h, false);
            /* Monitor: el de la ventana madre, el pedido por la app o el del puntero */
            Monitor mon = parent != null ? monitors.for_rect (parent.geom)
                        : unplaced ? pointer_monitor ()
                        : monitors.for_rect (g);
            var wa = mon.work;
            g.w = int.min (g.w, wa.w);
            g.h = int.min (g.h, wa.h);

            if (parent != null) {
                /* Diálogos centrados sobre su ventana madre */
                g.x = parent.geom.x + (parent.geom.w - g.w) / 2;
                g.y = parent.geom.y + (parent.geom.h - g.h) / 2;
            } else if (unplaced) {
                g.x = wa.x + (wa.w - g.w) / 2;
                g.y = wa.y + (wa.h - g.h) / 2;
            }
            /* Que la ventana quede siempre dentro del área útil */
            g.x = int.max (wa.x - (int) c.csd[0], int.min (g.x, wa.x + wa.w - g.w + (int) c.csd[1]));
            g.y = int.max (wa.y - (int) c.csd[2], int.min (g.y, wa.y + wa.h - g.h + (int) c.csd[3]));
            return g;
        }

        /* Monitor, tamaño y posición de una regla. Devuelve el monitor elegido. */
        Monitor? apply_rule_geometry (Client c, Rule rule) {
            Monitor? mon = null;
            if (rule.monitor != null) {
                var m = rule.monitor.down ();
                if (m == "principal" || m == "primary") {
                    mon = monitors.primary ();
                } else {
                    int i = int.parse (m) - 1;
                    if (i >= 0 && i < monitors.list.length) mon = monitors.list[i];
                }
            }
            var target = mon ?? monitor_of (c);
            var wa = target.work;
            var g = c.geom;
            int w, h;
            if (rule.parse_size (wa, out w, out h)) {
                c.hints.constrain (ref w, ref h, false);
                g.w = int.min (w, wa.w);
                g.h = int.min (h, wa.h);
            }
            int px, py;
            if (rule.parse_position (out px, out py)) {
                g.x = wa.x + px;
                g.y = wa.y + py;
            } else if (rule.centered () || mon != null || rule.size != null) {
                g.x = wa.x + (wa.w - g.w) / 2;
                g.y = wa.y + (wa.h - g.h) / 2;
            }
            c.geom = g;
            dpy.move_resize_window (c.win, g.x, g.y, g.w, g.h);
            return target;
        }

        void apply_geometry (Client c, Rect g) {
            g.w = int.max (g.w, 1);
            g.h = int.max (g.h, 1);
            c.geom = g;
            dpy.move_resize_window (c.win, g.x, g.y, g.w, g.h);
        }

        /* Convierte un rectángulo visible en la geometría X de la ventana,
         * sumando el margen de sombra de las apps con CSD. */
        /* Ajusta un rectángulo objetivo a los límites de tamaño de la app,
         * centrándola si no puede ocuparlo entero (p. ej. tamaño máximo). */
        Rect fit (Client c, Rect r) {
            int w = r.w, h = r.h;
            c.hints.constrain (ref w, ref h, false);
            return Rect (r.x + (r.w - w) / 2, r.y + (r.h - h) / 2, w, h);
        }

        Rect with_csd (Client c, Rect r) {
            return Rect (r.x - (int) c.csd[0], r.y - (int) c.csd[2],
                         r.w + (int) (c.csd[0] + c.csd[1]),
                         r.h + (int) (c.csd[2] + c.csd[3]));
        }

        /* ---------------------------------------------------------------- */
        /* Foco y apilado                                                    */
        /* ---------------------------------------------------------------- */

        void focus (Client? c, bool update_mru = true) {
            /* Si la ventana tiene un diálogo modal abierto, el foco va al diálogo */
            if (c != null) {
                var m = modal_child (c);
                if (m != null) {
                    c = m;
                }
            }
            var prev = focused;
            if (c == null || !c.can_focus ()) {
                focused = null;
                dpy.set_input_focus (root, Xc.REVERT_TO_POINTER_ROOT, Xc.CURRENT_TIME);
                set_prop (root, atoms.net_active_window, Xc.XA_WINDOW, { 0 });
                if (prev != null) grab_buttons (prev, false);
                return;
            }
            focused = c;
            if (prev != null && prev != c) {
                grab_buttons (prev, false);
            }
            grab_buttons (c, true);
            if (c.accepts_input) {
                dpy.set_input_focus (c.win, Xc.REVERT_TO_POINTER_ROOT, Xc.CURRENT_TIME);
            }
            if (c.urgent) {
                set_urgent (c, false);
            }
            if (c.supports_take_focus) {
                send_protocol (c, atoms.wm_take_focus);
            }
            set_prop (root, atoms.net_active_window, Xc.XA_WINDOW, { (long) c.win });
            if (update_mru) {
                mru.remove (c);
                mru.insert (0, c);
            }
        }

        void focus_next () {
            for (int i = 0; i < mru.length; i++) {
                if (mru[i].can_focus ()) {
                    focus (mru[i]);
                    raise (mru[i]);
                    return;
                }
            }
            focus (null);
        }

        void activate (Client c) {
            if (!c.on_desktop (current_desktop)) {
                switch_desktop (c.desktop);
            }
            if (c.minimized) {
                /* El foco, cuando la ventana ya esté visible tras la animación */
                raise (c);
                var win = c.win;
                unminimize (c, () => {
                    var still = find (win);
                    if (still != null) {
                        focus (still);
                        raise (still);
                    }
                });
                return;
            }
            focus (c);
            raise (c);
        }

        void raise (Client c) {
            if (c.kind.is_chrome ()) {
                return;
            }
            stacking.remove (c);
            stacking.add (c);
            /* Sus diálogos van siempre por encima */
            for (int i = 0; i < stacking.length; i++) {
                var t = stacking[i];
                if (t.transient_for == c.win) {
                    stacking.remove (t);
                    stacking.add (t);
                }
            }
            restack ();
            update_client_lists ();
        }

        /* Capas: escritorio < debajo < normal < encima < docks < pantalla completa enfocada */
        void restack () {
            var order = new GenericArray<Client> ();
            Layer[] layers = { Layer.DESKTOP, Layer.BELOW, Layer.NORMAL,
                               Layer.ABOVE, Layer.DOCK, Layer.FULLSCREEN };
            foreach (var l in layers) {
                stacking.foreach ((c) => { if (c.layer (c == focused) == l) order.add (c); });
            }
            order.foreach ((c) => { dpy.raise_window (c.win); });
            stacking = order;
        }

        void grab_buttons (Client c, bool is_focused) {
            dpy.ungrab_button (Xc.ANY_BUTTON, Xc.ANY_MODIFIER, c.win);
            if (!is_focused) {
                /* Clic para enfocar: se congela el clic, se enfoca y se reenvía. */
                dpy.grab_button (Xc.ANY_BUTTON, Xc.ANY_MODIFIER, c.win, false,
                                 (uint) Xc.BUTTON_PRESS_MASK, Xc.GRAB_MODE_SYNC,
                                 Xc.GRAB_MODE_ASYNC, 0, 0);
            }
            foreach (var extra in lock_variants ()) {
                foreach (uint b in new uint[] { 1, 3 }) {
                    dpy.grab_button (b, Xc.MOD1 | extra, c.win, false,
                                     (uint) (Xc.BUTTON_PRESS_MASK | Xc.BUTTON_RELEASE_MASK
                                             | Xc.POINTER_MOTION_MASK),
                                     Xc.GRAB_MODE_ASYNC, Xc.GRAB_MODE_ASYNC, 0, 0);
                }
            }
        }

        static uint[] lock_variants () {
            return { 0, Xc.LOCK, Xc.MOD2, Xc.LOCK | Xc.MOD2 };
        }

        /* ---------------------------------------------------------------- */
        /* Estados: minimizar, maximizar, ajustar, pantalla completa         */
        /* ---------------------------------------------------------------- */

        void minimize (Client c) {
            if (c.minimized || c.kind.is_chrome ()) {
                return;
            }
            if (c.anim != null) {
                c.anim.finish ();
            }
            /* Captura antes de ocultar, para la animación en el sitio */
            Rect shot_rect = c.geom;
            var shot = c.hidden_by_desktop ? null : snapshot (c, out shot_rect);
            c.minimized = true;
            set_anim (c, "minimize");
            c.ignore_unmaps++;
            if (shot != null && config.animations) {
                c.mini_snapshot = shot;
                c.mini_rect = shot_rect;
                /* Primero la animación encima (su primer fotograma es idéntico a la
                 * ventana) y luego ocultar la ventana ya tapada: sin fotograma vacío */
                start_minimize_anim (c, false, null);
                var win = c.win;
                Timeout.add (24, () => {
                    var still = find (win);
                    if (still != null) {
                        if (still.minimized) {
                            dpy.unmap_window (still.win);
                        } else {
                            still.ignore_unmaps--;  /* se restauró antes de ocultarse */
                        }
                        dpy.flush ();
                    }
                    return Source.REMOVE;
                });
            } else {
                dpy.unmap_window (c.win);
            }
            set_wm_state (c, Xc.ICONIC_STATE);
            update_net_wm_state (c);
            if (focused == c) {
                focused = null;
                focus_next ();
            }
        }

        /* Restaurar: la captura sube, crece y aparece en su sitio y, al terminar,
         * se muestra la ventana real; «after» se ejecuta entonces (p. ej. enfocar). */
        void unminimize (Client c, owned MinimizeAnimation.Done? after = null) {
            if (c.anim != null) {
                c.anim.finish ();
            }
            c.minimized = false;
            set_wm_state (c, Xc.NORMAL_STATE);
            update_net_wm_state (c);
            if (c.mini_snapshot != null && !c.hidden_by_desktop) {
                var win = c.win;
                start_minimize_anim (c, true, () => {
                    var still = find (win);
                    if (still != null && !still.minimized && !still.hidden_by_desktop) {
                        set_anim (still, "minimize");
                        /* La ventana real aparece DEBAJO de la captura; la captura
                         * se retira cuando la app ya se ha dibujado (on_painted) */
                        wait_for_paint (still);
                        dpy.map_window (still.win);
                        if (after != null) after ();
                        if (still.anim != null && !still.anim.finished) {
                            still.anim.raise_above ();
                        }
                    }
                });
                c.mini_snapshot = null;
                return;
            }
            c.mini_snapshot = null;
            set_anim (c, "minimize");
            dpy.map_window (c.win);
            if (after != null) after ();
        }

        /* DAMAGE avisa cuando la ventana recién mostrada ya tiene contenido. */
        void wait_for_paint (Client c) {
            if (damage_event_base < 0) {
                return;  /* sin DAMAGE: la captura se retira a los 300 ms */
            }
            if (c.paint_damage != 0) {
                Xd.destroy (dpy, c.paint_damage);
            }
            c.paint_damage = Xd.create (dpy, c.win, Xd.REPORT_NON_EMPTY);
        }

        void on_painted (X.Window w) {
            var c = find (w);
            if (c == null || c.paint_damage == 0) {
                return;
            }
            Xd.destroy (dpy, c.paint_damage);
            c.paint_damage = 0;
            /* Dos fotogramas para que el compositor muestre lo pintado */
            var anim = c.anim;
            Timeout.add (32, () => {
                if (anim != null) {
                    anim.finish ();
                }
                return Source.REMOVE;
            });
        }

        void start_minimize_anim (Client c, bool restoring, owned MinimizeAnimation.Done? done) {
            var snap = c.mini_snapshot;
            if (snap == null) {
                if (done != null) done ();
                return;
            }
            var anim = new MinimizeAnimation (dpy, root, screen, atoms, snap, c.mini_rect,
                                              restoring, (owned) done);
            c.anim = anim;
            anim.start ();
        }

        /* Captura de la parte visible de una ventana. */
        Cairo.ImageSurface? snapshot (Client c, out Rect area) {
            var g = c.geom;
            int x0 = int.max (g.x, 0), y0 = int.max (g.y, 0);
            int x1 = int.min (g.x + g.w, screen_w), y1 = int.min (g.y + g.h, screen_h);
            area = Rect (x0, y0, x1 - x0, y1 - y0);
            if (area.w < 16 || area.h < 16) {
                return null;
            }
            last_error = 0;
            var img = Xx.get_image (dpy, c.win, x0 - g.x, y0 - g.y, area.w, area.h,
                                    ulong.MAX /* AllPlanes */, 2 /* ZPixmap */);
            if (img == null || last_error != 0 || img.bits_per_pixel != 32) {
                return null;
            }
            var full = new Cairo.ImageSurface (img.depth == 32 ? Cairo.Format.ARGB32 : Cairo.Format.RGB24,
                                               area.w, area.h);
            full.flush ();
            uchar* dst = full.get_data ();
            int stride = full.get_stride ();
            uchar* src = (uchar*) img.data;
            for (int y = 0; y < area.h; y++) {
                Memory.copy (dst + y * stride, src + y * img.bytes_per_line, area.w * 4);
            }
            full.mark_dirty ();
            /* A resolución completa: la animación se ve casi a tamaño real (90-100 %) */
            return full;
        }

        void set_maximized (Client c, bool on, Monitor? target = null) {
            if (c.kind.is_chrome () || c.fullscreen || (on && c.hints.fixed ())) {
                return;
            }
            if (on) {
                c.save_restore ();
                c.snapped = false;
                c.snap_zone = SnapZone.NONE;
                c.maximized = true;
                apply_geometry (c, fit (c, with_csd (c, (target ?? monitor_of (c)).work)));
            } else {
                c.maximized = false;
                c.snapped = false;
                c.snap_zone = SnapZone.NONE;
                restore_geometry (c);
            }
            update_net_wm_state (c);
        }

        /* Ajusta la ventana a una zona (mitad, cuarto o maximizar).
         * Sin monitor explícito (teclado): repetir la misma mitad salta al
         * monitor vecino, a la mitad opuesta. */
        void snap (Client c, SnapZone zone, Monitor? target = null) {
            if (zone == SnapZone.MAXIMIZE) {
                set_maximized (c, true, target);
                return;
            }
            if (zone == SnapZone.NONE) {
                set_maximized (c, false);
                return;
            }
            if (c.kind.is_chrome () || c.fullscreen || c.hints.fixed ()) {
                return;
            }
            var mon = target ?? monitor_of (c);
            if (target == null && c.snapped && c.snap_zone == zone
                && (zone == SnapZone.LEFT || zone == SnapZone.RIGHT)) {
                var next = monitors.neighbor (mon, zone.side ());
                if (next != null) {
                    snap (c, zone.mirrored (), next);
                }
                return;
            }
            c.save_restore ();
            c.maximized = false;
            c.snapped = true;
            c.snap_zone = zone;
            apply_geometry (c, fit (c, with_csd (c, zone.rect (mon.work))));
            update_net_wm_state (c);
        }

        void set_fullscreen (Client c, bool on) {
            if (c.kind.is_chrome () || c.fullscreen == on) {
                return;
            }
            if (on) {
                c.save_restore ();
                c.fullscreen = true;
                apply_geometry (c, monitor_of (c).geom);
            } else {
                c.fullscreen = false;
                if (c.maximized) {
                    apply_geometry (c, fit (c, with_csd (c, monitor_of (c).work)));
                } else {
                    restore_geometry (c);
                }
            }
            update_net_wm_state (c);
            restack ();
        }

        void restore_geometry (Client c) {
            if (c.has_restore) {
                apply_geometry (c, c.restore);
                c.has_restore = false;
            }
        }

        void close (Client c) {
            if (c.supports_delete) {
                send_protocol (c, atoms.wm_delete_window);
            } else {
                Xx.kill_client (dpy, c.win);
            }
        }

        /* ---------------------------------------------------------------- */
        /* Ratón                                                             */
        /* ---------------------------------------------------------------- */

        void on_button_press (ref X.ButtonEvent e) {
            var c = find (e.window);
            if (c == null) {
                dpy.allow_events (Xc.REPLAY_POINTER, Xc.CURRENT_TIME);
                return;
            }
            bool alt = (e.state & Xc.MOD1) != 0;
            if (alt && (e.button == 1 || e.button == 3) && !c.kind.is_chrome () && !c.fullscreen
                && !(e.button == 3 && c.hints.fixed ())) {
                focus (c);
                raise (c);
                if (e.button == 1) {
                    begin_drag (c, DragMode.MOVE, DIR_MOVE, e.x_root, e.y_root);
                } else {
                    begin_drag (c, DragMode.RESIZE, nearest_corner (c, e.x_root, e.y_root),
                                e.x_root, e.y_root);
                }
                return;
            }
            if (c.can_focus ()) {
                focus (c);
                raise (c);
            }
            dpy.allow_events (Xc.REPLAY_POINTER, Xc.CURRENT_TIME);
        }

        int nearest_corner (Client c, int px, int py) {
            bool left = px < c.geom.x + c.geom.w / 2;
            bool top = py < c.geom.y + c.geom.h / 2;
            if (top) return left ? DIR_TOPLEFT : DIR_TOPRIGHT;
            return left ? DIR_BOTTOMLEFT : DIR_BOTTOMRIGHT;
        }

        void begin_drag (Client c, DragMode mode, int dir, int px, int py) {
            if (c.kind.is_chrome () || c.fullscreen) {
                return;
            }
            /* Arrastrar una ventana maximizada/ajustada la devuelve a su tamaño,
             * manteniendo el puntero en la misma proporción horizontal. */
            if (mode == DragMode.MOVE && (c.maximized || c.snapped) && c.has_restore) {
                double ratio = (px - c.geom.x) / (double) int.max (c.geom.w, 1);
                var r = c.restore;
                r.x = px - (int) (r.w * ratio);
                r.y = c.geom.y;
                c.maximized = false;
                c.snapped = false;
                c.has_restore = false;
                apply_geometry (c, r);
                update_net_wm_state (c);
            }
            drag = mode;
            drag_client = c;
            drag_dir = dir;
            drag_px = px;
            drag_py = py;
            drag_start = c.geom;
            links = new GenericArray<ResizeLink> ();
            if (mode == DragMode.RESIZE) {
                /* Redimensionar a mano deja de ser "mitad"/"maximizada" */
                if (c.snapped || c.maximized) {
                    c.snapped = false;
                    c.maximized = false;
                    update_net_wm_state (c);
                }
                if (config.linked_resize) {
                    find_resize_links (c, dir);
                }
            }
            uint shape = mode == DragMode.MOVE ? Xc.XC_FLEUR : Xc.XC_BOTTOM_RIGHT_CORNER;
            dpy.grab_pointer (root, false,
                              (uint) (Xc.BUTTON_RELEASE_MASK | Xc.POINTER_MOTION_MASK),
                              Xc.GRAB_MODE_ASYNC, Xc.GRAB_MODE_ASYNC, 0,
                              (uint) Xx.create_font_cursor (dpy, shape), Xc.CURRENT_TIME);
        }

        void on_motion (int x, int y) {
            if (drag == DragMode.NONE || drag_client == null) {
                return;
            }
            int dx = x - drag_px;
            int dy = y - drag_py;
            var g = drag_start;
            if (drag == DragMode.MOVE) {
                g.x += dx;
                g.y += dy;
                update_snap_preview (x, y);
            } else {
                int d = drag_dir;
                bool l = d == DIR_LEFT || d == DIR_TOPLEFT || d == DIR_BOTTOMLEFT;
                bool r = d == DIR_RIGHT || d == DIR_TOPRIGHT || d == DIR_BOTTOMRIGHT;
                bool t = d == DIR_TOP || d == DIR_TOPLEFT || d == DIR_TOPRIGHT;
                bool b = d == DIR_BOTTOM || d == DIR_BOTTOMLEFT || d == DIR_BOTTOMRIGHT;
                var c = drag_client;
                /* Desplazamiento de cada borde, en coordenadas visibles */
                var av = LinkedResize.visible (c, drag_start);
                int dl = l ? dx : 0, dr = r ? dx : 0, dt = t ? dy : 0, db = b ? dy : 0;
                LinkedResize.clamp (ref dl, ref dr, ref dt, ref db, av,
                                    LinkedResize.min_w (c), LinkedResize.min_h (c), links);
                g = with_csd (c, Rect (av.x + dl, av.y + dt, av.w + dr - dl, av.h + db - dt));
                if (links.length == 0) {
                    /* Sola: incrementos de terminal (de carácter en carácter) */
                    int w = g.w, h = g.h;
                    c.hints.constrain (ref w, ref h, true);
                    if (l) g.x += g.w - w;
                    if (t) g.y += g.h - h;
                    g.w = w;
                    g.h = h;
                } else {
                    /* Enlazada: las vecinas siguen al borde común, sin huecos */
                    for (int i = 0; i < links.length; i++) {
                        var k = links[i];
                        apply_geometry (k.c, with_csd (k.c, LinkedResize.moved (k, dl, dr, dt, db)));
                    }
                }
            }
            apply_geometry (drag_client, g);
        }

        /* Mientras se arrastra: zona bajo el puntero y su vista previa. */
        void update_snap_preview (int x, int y) {
            var c = drag_client;
            Monitor mon;
            var zone = SnapZone.at_pointer (monitors, x, y, out mon);
            if (c == null || c.hints.fixed ()) {
                zone = SnapZone.NONE;
            }
            drag_zone = zone;
            drag_zone_mon = mon;
            preview.update (zone, zone.rect (mon.work), c != null ? c.win : 0);
        }

        void on_button_release (int x, int y) {
            if (drag == DragMode.NONE) {
                return;
            }
            var c = drag_client;
            var mode = drag;
            var zone = drag_zone;
            var mon = drag_zone_mon;
            end_drag ();
            if (c == null || mode != DragMode.MOVE || zone == SnapZone.NONE || mon == null) {
                return;
            }
            /* Soltar en un borde exterior: mitad, cuarto (esquinas) o maximizar (arriba) */
            snap (c, zone, mon);
        }

        /* Ventanas pegadas al borde que se va a arrastrar (mismo escritorio, visibles). */
        void find_resize_links (Client c, int dir) {
            var cands = new GenericArray<Client> ();
            clients.foreach ((o) => {
                if (o != c && !o.kind.is_chrome () && !o.minimized && !o.hidden_by_desktop
                    && !o.fullscreen && o.transient_for == 0 && o.on_desktop (current_desktop)) {
                    cands.add (o);
                }
            });
            bool l = dir == DIR_LEFT || dir == DIR_TOPLEFT || dir == DIR_BOTTOMLEFT;
            bool r = dir == DIR_RIGHT || dir == DIR_TOPRIGHT || dir == DIR_BOTTOMRIGHT;
            bool t = dir == DIR_TOP || dir == DIR_TOPLEFT || dir == DIR_TOPRIGHT;
            bool b = dir == DIR_BOTTOM || dir == DIR_BOTTOMLEFT || dir == DIR_BOTTOMRIGHT;
            links = LinkedResize.find (LinkedResize.visible (c, c.geom), l, r, t, b, cands);
            for (int i = 0; i < links.length; i++) {
                var k = links[i].c;
                if (k.snapped || k.maximized) {
                    k.snapped = false;
                    k.maximized = false;
                    update_net_wm_state (k);
                }
            }
            if (links.length > 0) {
                debug ("redimensionado enlazado con %d ventana(s)", links.length);
            }
        }

        void end_drag () {
            links = new GenericArray<ResizeLink> ();
            drag = DragMode.NONE;
            drag_client = null;
            drag_zone = SnapZone.NONE;
            drag_zone_mon = null;
            if (preview != null) {
                preview.hide ();
            }
            dpy.ungrab_pointer (Xc.CURRENT_TIME);
        }

        /* ---------------------------------------------------------------- */
        /* Teclado                                                           */
        /* ---------------------------------------------------------------- */

        struct Binding {
            uint mods;
            ulong keysym;
        }

        static Binding[] bindings () {
            return {
                { Xc.MOD1, Xc.XK_TAB },                 /* Alt+Tab: siguiente ventana */
                { Xc.MOD1 | Xc.SHIFT, Xc.XK_TAB },      /* Alt+Shift+Tab: anterior */
                { Xc.MOD1, Xc.XK_F4 },                  /* Alt+F4: cerrar */
                { Xc.MOD4, Xc.XK_LEFT },                /* Super+←: mitad izquierda */
                { Xc.MOD4, Xc.XK_RIGHT },               /* Super+→: mitad derecha */
                { Xc.MOD4, Xc.XK_UP },                  /* Super+↑: maximizar */
                { Xc.MOD4, Xc.XK_DOWN },                /* Super+↓: restaurar / minimizar */
                { Xc.MOD4 | Xc.SHIFT, Xc.XK_LEFT },     /* Super+Shift+←: monitor izquierdo */
                { Xc.MOD4 | Xc.SHIFT, Xc.XK_RIGHT },    /* Super+Shift+→: monitor derecho */
                { Xc.MOD4, Xc.XK_T },                   /* Super+T: siempre encima */
                { Xc.MOD1, Xc.XK_GRAVE },               /* Alt+`: ventanas de la misma app */
                { Xc.CONTROL | Xc.MOD1, Xc.XK_LEFT },   /* Ctrl+Alt+←/→: escritorio anterior/siguiente */
                { Xc.CONTROL | Xc.MOD1, Xc.XK_RIGHT },
                { Xc.CONTROL | Xc.MOD1 | Xc.SHIFT, Xc.XK_LEFT },  /* + Shift: llevar la ventana */
                { Xc.CONTROL | Xc.MOD1 | Xc.SHIFT, Xc.XK_RIGHT }
            };
        }

        /* Super+1…9: ir al escritorio; Super+Shift+1…9: enviar la ventana */
        static bool is_digit (ulong sym) {
            return sym >= Xc.XK_1 && sym <= Xc.XK_9;
        }

        void grab_keys () {
            dpy.ungrab_key (0 /* AnyKey */, Xc.ANY_MODIFIER, root);
            foreach (var b in bindings ()) {
                int code = Xx.keysym_to_keycode (dpy, b.keysym);
                if (code == 0) {
                    continue;
                }
                foreach (var extra in lock_variants ()) {
                    dpy.grab_key (code, b.mods | extra, root, true,
                                  Xc.GRAB_MODE_ASYNC, Xc.GRAB_MODE_ASYNC);
                }
            }
            for (ulong sym = Xc.XK_1; sym <= Xc.XK_9; sym++) {
                int code = Xx.keysym_to_keycode (dpy, sym);
                if (code == 0) continue;
                foreach (var extra in lock_variants ()) {
                    dpy.grab_key (code, Xc.MOD4 | extra, root, true, Xc.GRAB_MODE_ASYNC, Xc.GRAB_MODE_ASYNC);
                    dpy.grab_key (code, Xc.MOD4 | Xc.SHIFT | extra, root, true, Xc.GRAB_MODE_ASYNC, Xc.GRAB_MODE_ASYNC);
                }
            }
        }

        void on_key_press (ref X.KeyEvent e) {
            ulong sym = dpy.keycode_to_keysym ((uchar) e.keycode, 0);
            uint mods = e.state & (Xc.SHIFT | Xc.CONTROL | Xc.MOD1 | Xc.MOD4);

            /* Con el Alt+Tab abierto el teclado es nuestro */
            if (cycling) {
                if (sym == Xc.XK_ESCAPE) {
                    end_cycle (false);
                } else if (sym == Xc.XK_TAB) {
                    cycle ((mods & Xc.SHIFT) != 0 ? -1 : 1);
                } else if (sym == Xc.XK_LEFT) {
                    cycle (-1);
                } else if (sym == Xc.XK_RIGHT) {
                    cycle (1);
                } else if (sym == Xc.XK_RETURN) {
                    end_cycle (true);
                }
                return;
            }
            if (mods == Xc.MOD1 && sym == Xc.XK_GRAVE) {
                cycle_app_windows ();
                return;
            }

            if (sym == Xc.XK_TAB && (mods & Xc.MOD1) != 0) {
                cycle ((mods & Xc.SHIFT) != 0 ? -1 : 1);
                return;
            }
            if (mods == (Xc.CONTROL | Xc.MOD1) && (sym == Xc.XK_LEFT || sym == Xc.XK_RIGHT)) {
                switch_desktop_relative (sym == Xc.XK_LEFT ? -1 : 1);
                return;
            }
            if (mods == Xc.MOD4 && is_digit (sym)) {
                switch_desktop ((uint) (sym - Xc.XK_1));
                return;
            }
            var c = focused;
            if (c == null) {
                return;
            }
            if (mods == (Xc.CONTROL | Xc.MOD1 | Xc.SHIFT) && (sym == Xc.XK_LEFT || sym == Xc.XK_RIGHT)) {
                uint target = wrap_desktop ((int) current_desktop + (sym == Xc.XK_LEFT ? -1 : 1));
                move_to_desktop (c, target, true);
                return;
            }
            if (mods == (Xc.MOD4 | Xc.SHIFT) && is_digit (sym)) {
                move_to_desktop (c, (uint) (sym - Xc.XK_1), false);
                return;
            }
            if (mods == Xc.MOD4 && sym == Xc.XK_T) {
                set_above (c, !c.above);
                return;
            }
            if (mods == Xc.MOD1 && sym == Xc.XK_F4) {
                close (c);
            } else if (mods == Xc.MOD4 && sym == Xc.XK_LEFT) {
                snap (c, SnapZone.LEFT);
            } else if (mods == Xc.MOD4 && sym == Xc.XK_RIGHT) {
                snap (c, SnapZone.RIGHT);
            } else if (mods == Xc.MOD4 && sym == Xc.XK_UP) {
                /* Mitad → cuarto superior → maximizar; sin ajustar: maximizar/restaurar */
                if (c.snapped) {
                    snap (c, c.snap_zone.up ());
                } else {
                    set_maximized (c, !c.maximized);
                }
            } else if (mods == (Xc.MOD4 | Xc.SHIFT) && sym == Xc.XK_LEFT) {
                move_to_neighbor (c, -1);
            } else if (mods == (Xc.MOD4 | Xc.SHIFT) && sym == Xc.XK_RIGHT) {
                move_to_neighbor (c, 1);
            } else if (mods == Xc.MOD4 && sym == Xc.XK_DOWN) {
                /* Mitad → cuarto inferior → restaurar; restaurada → minimizar */
                if (c.snapped) {
                    snap (c, c.snap_zone.down ());
                } else if (c.maximized) {
                    set_maximized (c, false);
                } else {
                    minimize (c);
                }
            }
        }

        /* Alt+Tab al estilo macOS: una entrada por aplicación, en orden de uso
         * reciente; el panel aparece tras un instante (un toque rápido no
         * parpadea) y se confirma al soltar Alt. Esc cancela. */
        void cycle (int step) {
            if (!cycling) {
                sw_items = build_switcher_items ();
                if (sw_items.length == 0
                    || (sw_items.length == 1 && focused != null && sw_items[0].top.app_key () == focused.app_key ())) {
                    return;
                }
                cycling = true;
                /* Si la app activa encabeza la lista, Alt+Tab va a la siguiente */
                cycle_index = (focused != null && sw_items[0].key == focused.app_key ()) ? 0 : -1;
                Xx.grab_keyboard (dpy, root, true, Xc.GRAB_MODE_ASYNC, Xc.GRAB_MODE_ASYNC,
                                  Xc.CURRENT_TIME);
                sw_timer = Timeout.add (Style.SWITCHER_DELAY_MS, () => {
                    sw_timer = 0;
                    if (cycling) {
                        sw_items.foreach ((it) => { ensure_icon (it.top); });
                        var mon = focused != null ? monitor_of (focused) : pointer_monitor ();
                        switcher.show (sw_items, cycle_index, mon);
                    }
                    return Source.REMOVE;
                });
            }
            int n = sw_items.length;
            cycle_index = ((cycle_index + step) % n + n) % n;
            switcher.select (cycle_index);
        }

        GenericArray<SwitcherItem> build_switcher_items () {
            var list = new GenericArray<SwitcherItem> ();
            var by_app = new HashTable<string, SwitcherItem> (str_hash, str_equal);
            mru.foreach ((c) => {
                if (c.kind.is_chrome () || c.skip_taskbar || !c.on_desktop (current_desktop)) return;
                if (c.transient_for != 0) return; /* los diálogos van con su app */
                var key = c.app_key ();
                var it = by_app[key];
                if (it != null) {
                    it.windows++;
                } else {
                    it = new SwitcherItem (key, c);
                    by_app[key] = it;
                    list.add (it);
                }
            });
            return list;
        }

        void on_key_release (ref X.KeyEvent e) {
            if (!cycling) {
                return;
            }
            ulong sym = dpy.keycode_to_keysym ((uchar) e.keycode, 0);
            if (sym == 0xffe9 /* Alt_L */ || sym == 0xffea /* Alt_R */) {
                end_cycle (true);
            }
        }

        void end_cycle (bool commit) {
            if (!cycling) {
                return;
            }
            cycling = false;
            if (sw_timer != 0) {
                Source.remove (sw_timer);
                sw_timer = 0;
            }
            switcher.hide ();
            Xx.ungrab_keyboard (dpy, Xc.CURRENT_TIME);
            if (commit && cycle_index >= 0 && cycle_index < sw_items.length) {
                activate (sw_items[cycle_index].top);
            }
            sw_items = new GenericArray<SwitcherItem> ();
        }

        /* Alt+`: rota entre las ventanas de la app activa (la menos reciente sube). */
        void cycle_app_windows () {
            if (focused == null) {
                return;
            }
            var key = focused.app_key ();
            Client? last = null;
            mru.foreach ((c) => {
                if (c != focused && c.app_key () == key && !c.kind.is_chrome ()
                    && c.on_desktop (current_desktop) && c.transient_for == 0) {
                    last = c;
                }
            });
            if (last != null) {
                activate (last);
            }
        }

        /* ---------------------------------------------------------------- */
        /* Iconos                                                            */
        /* ---------------------------------------------------------------- */

        string read_title (X.Window w) {
            var b = get_bytes (w, atoms.net_wm_name, atoms.utf8_string);
            if (b.length == 0) {
                b = get_bytes (w, (X.Atom) 39 /* WM_NAME */, (X.Atom) 31 /* STRING */);
            }
            return b.length > 0 ? ((string) b).make_valid () : "";
        }

        void read_wm_class (Client c) {
            var b = get_bytes (c.win, atoms.wm_class, (X.Atom) 31 /* STRING */);
            if (b.length == 0) return;
            /* "instancia\0clase\0" */
            int i = 0;
            while (i < b.length && b[i] != 0) i++;
            c.wm_instance = ((string) b).substring (0, i).make_valid ();
            int j = i + 1;
            int k = j;
            while (k < b.length && b[k] != 0) k++;
            if (j < b.length) {
                var tail = new uint8[k - j + 1];
                Memory.copy (tail, &b[j], k - j);
                tail[k - j] = 0;
                c.wm_class = ((string) tail).make_valid ();
            }
        }

        /* Icono de la ventana: _NET_WM_ICON o, si no lo trae, el del tema
         * según su .desktop; en ese caso se lo asignamos a la ventana. */
        void ensure_icon (Client c) {
            if (c.icon_loaded) {
                return;
            }
            c.icon_loaded = true;
            var data = get_longs (c.win, atoms.net_wm_icon, Xc.XA_CARDINAL, 1 << 20);
            c.icon = Icons.from_net_wm_icon (data, Icons.SIZE);
            if (c.icon == null) {
                c.icon = icons.from_theme (c.wm_instance, c.wm_class);
                if (c.icon != null) {
                    set_prop (c.win, atoms.net_wm_icon, Xc.XA_CARDINAL, Icons.to_net_wm_icon (c.icon));
                    debug ("icono asignado a %s desde el tema", c.wm_class);
                    /* El PropertyNotify invalidará la caché; no hace falta recargar */
                }
            }
        }

        /* ---------------------------------------------------------------- */
        /* Propiedades EWMH / ICCCM                                         */
        /* ---------------------------------------------------------------- */

        Client? find (X.Window w) {
            for (int i = 0; i < clients.length; i++) {
                if (clients[i].win == w) {
                    return clients[i];
                }
            }
            return null;
        }

        void set_prop (X.Window w, X.Atom prop, ulong type, long[] data) {
            Xx.change_property (dpy, w, prop, (X.Atom) type, 32, Xc.PROP_MODE_REPLACE,
                                (void*) data, data.length);
        }

        long[] get_longs (X.Window w, X.Atom prop, X.Atom type, long max) {
            X.Atom actual;
            int format;
            ulong n, after;
            void* data = null;
            last_error = 0;
            int status = Xx.get_window_property (dpy, w, prop, 0, max, false, type,
                                                 out actual, out format, out n, out after,
                                                 out data);
            long[] result = {};
            if (status == 0 && last_error == 0 && data != null && format == 32) {
                long* p = (long*) data;
                for (ulong i = 0; i < n; i++) {
                    result += p[i];
                }
            }
            if (data != null) {
                Xx.free (data);
            }
            return result;
        }

        uint8[] get_bytes (X.Window w, X.Atom prop, X.Atom type) {
            X.Atom actual;
            int format;
            ulong n, after;
            void* data = null;
            last_error = 0;
            int status = Xx.get_window_property (dpy, w, prop, 0, 1024, false, type,
                                                 out actual, out format, out n, out after, out data);
            uint8[] result = new uint8[0];
            if (status == 0 && last_error == 0 && data != null && format == 8) {
                result = new uint8[n + 1];
                Memory.copy (result, data, n);
                result[n] = 0;
                result.length = (int) n;
            }
            if (data != null) {
                Xx.free (data);
            }
            return result;
        }

        Rect read_geometry (X.Window w) {
            X.WindowAttributes a;
            dpy.get_window_attributes (w, out a);
            return Rect (a.x, a.y, a.width, a.height);
        }

        ClientKind read_kind (X.Window w) {
            foreach (var t in get_longs (w, atoms.net_wm_window_type, Xc.XA_ATOM, 16)) {
                var a = (X.Atom) t;
                if (a == atoms.net_wm_window_type_dock) return ClientKind.DOCK;
                if (a == atoms.net_wm_window_type_desktop) return ClientKind.DESKTOP;
                if (a == atoms.net_wm_window_type_dialog) return ClientKind.DIALOG;
                if (a == atoms.net_wm_window_type_utility) return ClientKind.UTILITY;
                if (a == atoms.net_wm_window_type_splash) return ClientKind.SPLASH;
                if (a == atoms.net_wm_window_type_normal) return ClientKind.NORMAL;
            }
            return ClientKind.NORMAL;
        }

        void read_struts (Client c) {
            var s = get_longs (c.win, atoms.net_wm_strut_partial, Xc.XA_CARDINAL, 12);
            if (s.length < 12) {
                /* _NET_WM_STRUT clásico: el strut cubre todo el borde */
                var b = get_longs (c.win, atoms.net_wm_strut, Xc.XA_CARDINAL, 4);
                long[] full = { 0, 0, 0, 0,
                                0, screen_h - 1, 0, screen_h - 1,
                                0, screen_w - 1, 0, screen_w - 1 };
                for (int i = 0; i < 4; i++) {
                    full[i] = i < b.length ? b[i] : 0;
                }
                s = full;
            }
            for (int i = 0; i < 12; i++) {
                c.strut[i] = s[i];
            }
        }

        void read_csd (Client c) {
            var e = get_longs (c.win, atoms.gtk_frame_extents, Xc.XA_CARDINAL, 4);
            for (int i = 0; i < 4; i++) {
                c.csd[i] = i < e.length ? e[i] : 0;
            }
        }

        void update_workarea () {
            long l = 0, r = 0, t = 0, b = 0;
            clients.foreach ((c) => {
                l = long.max (l, c.strut[0]);
                r = long.max (r, c.strut[1]);
                t = long.max (t, c.strut[2]);
                b = long.max (b, c.strut[3]);
            });
            workarea = Rect ((int) l, (int) t, screen_w - (int) (l + r), screen_h - (int) (t + b));
            long[] wa = {};
            for (uint i = 0; i < n_desktops; i++) {
                wa += workarea.x;
                wa += workarea.y;
                wa += workarea.w;
                wa += workarea.h;
            }
            set_prop (root, atoms.net_workarea, Xc.XA_CARDINAL, wa);
            monitors.apply_struts (clients, screen_w, screen_h);
            reapply_states ();
        }

        /* Reajusta las ventanas cuya geometría depende del monitor. */
        void reapply_states () {
            clients.foreach ((c) => {
                if (c.kind.is_chrome ()) return;
                var mon = monitor_of (c);
                if (c.fullscreen) {
                    apply_geometry (c, mon.geom);
                } else if (c.maximized) {
                    apply_geometry (c, fit (c, with_csd (c, mon.work)));
                } else if (c.snapped) {
                    c.snapped = false;    /* snap() lo vuelve a marcar */
                    snap (c, c.snap_zone, mon);
                }
            });
        }

        /* ---------------------------------------------------------------- */
        /* Monitores                                                         */
        /* ---------------------------------------------------------------- */

        Monitor monitor_of (Client c) {
            return monitors.for_rect (c.geom);
        }

        Monitor pointer_monitor () {
            X.Window r, child;
            int x, y, wx, wy;
            uint mask;
            if (Xx.query_pointer (dpy, root, out r, out child, out x, out y, out wx, out wy, out mask)) {
                return monitors.at (x, y);
            }
            return focused != null ? monitor_of (focused) : monitors.primary ();
        }

        string describe_monitors () {
            var sb = new StringBuilder ();
            sb.append_printf ("%d monitor(es):", monitors.list.length);
            monitors.list.foreach ((m) => {
                sb.append_printf (" %s %dx%d+%d+%d%s", m.name, m.geom.w, m.geom.h,
                                  m.geom.x, m.geom.y, m.primary ? " (principal)" : "");
            });
            return sb.str;
        }

        /* Mueve la ventana al monitor vecino conservando su posición relativa
         * y su estado (maximizada, ajustada o pantalla completa). */
        void move_to_neighbor (Client c, int dir) {
            if (c.kind.is_chrome ()) return;
            var from = monitor_of (c);
            var to = monitors.neighbor (from, dir);
            if (to == null) return;
            move_to_monitor (c, from, to);
        }

        static Rect translate_rect (Rect r, Monitor from, Monitor to) {
            var f = from.work;
            var t = to.work;
            int w = int.min (r.w, t.w);
            int h = int.min (r.h, t.h);
            int x = t.x + (int) ((r.x - f.x) * (double) (t.w - w) / int.max (f.w - r.w, 1));
            int y = t.y + (int) ((r.y - f.y) * (double) (t.h - h) / int.max (f.h - r.h, 1));
            x = int.max (t.x, int.min (x, t.x + t.w - w));
            y = int.max (t.y, int.min (y, t.y + t.h - h));
            return Rect (x, y, w, h);
        }

        void move_to_monitor (Client c, Monitor from, Monitor to) {
            if (c.has_restore) {
                c.restore = translate_rect (c.restore, from, to);
            }
            if (c.fullscreen) {
                apply_geometry (c, to.geom);
            } else if (c.maximized) {
                apply_geometry (c, fit (c, with_csd (c, to.work)));
            } else if (c.snapped) {
                c.snapped = false;
                snap (c, c.snap_zone, to);
            } else {
                apply_geometry (c, translate_rect (c.geom, from, to));
            }
        }

        /* Se conectó, desconectó o reorganizó un monitor. */
        /* Tamaño real de la ventana raíz. XDisplayWidth puede quedar desfasado
         * (p. ej. con Xinerama, donde RandR solo describe una pantalla). */
        void read_root_size () {
            X.Window r;
            int x, y;
            uint w, h, bw, depth;
            dpy.get_geometry (root, out r, out x, out y, out w, out h, out bw, out depth);
            screen_w = (int) w;
            screen_h = (int) h;
        }

        bool same_layout (GenericArray<Monitor> a, GenericArray<Monitor> b) {
            if (a.length != b.length) return false;
            for (int i = 0; i < a.length; i++) {
                var p = a[i].geom;
                var q = b[i].geom;
                if (p.x != q.x || p.y != q.y || p.w != q.w || p.h != q.h || a[i].primary != b[i].primary) {
                    return false;
                }
            }
            return true;
        }

        void on_screen_change () {
            int old_w = screen_w, old_h = screen_h;
            read_root_size ();
            var old = monitors.list;
            /* Recordar en qué monitor estaba cada ventana antes del cambio */
            var where = new HashTable<Client, Monitor> (direct_hash, direct_equal);
            clients.foreach ((c) => { if (!c.kind.is_chrome ()) where[c] = monitors.for_rect (c.geom); });

            monitors.refresh (dpy, root, screen_w, screen_h);
            if (old_w == screen_w && old_h == screen_h && same_layout (old, monitors.list)) {
                return;  /* aviso sin cambios reales */
            }
            clients.foreach ((c) => { if (c.kind == ClientKind.DOCK) read_struts (c); });
            update_workarea ();

            /* Ventanas que se quedaron fuera de todo monitor → al principal */
            clients.foreach ((c) => {
                if (c.kind.is_chrome ()) return;
                int cx = c.geom.x + c.geom.w / 2, cy = c.geom.y + c.geom.h / 2;
                if (!monitors.covers (cx, cy)) {
                    var from = where[c];
                    if (from != null) {
                        move_to_monitor (c, from, monitors.primary ());
                    }
                }
            });
            update_desktop_props ();
            message ("Cambio de pantallas: %dx%d, %s", screen_w, screen_h, describe_monitors ());
        }

        /* ---------------------------------------------------------------- */
        /* Escritorios virtuales                                             */
        /* ---------------------------------------------------------------- */

        void update_desktop_props () {
            set_prop (root, atoms.net_number_of_desktops, Xc.XA_CARDINAL, { (long) n_desktops });
            set_prop (root, atoms.net_current_desktop, Xc.XA_CARDINAL, { (long) current_desktop });
            set_prop (root, atoms.net_desktop_geometry, Xc.XA_CARDINAL, { screen_w, screen_h });
            long[] viewport = new long[n_desktops * 2];
            set_prop (root, atoms.net_desktop_viewport, Xc.XA_CARDINAL, viewport);
            var names = new ByteArray ();
            for (uint i = 0; i < n_desktops; i++) {
                names.append ("Escritorio %u".printf (i + 1).data);
                names.append ({ 0 });
            }
            Xx.change_property (dpy, root, atoms.net_desktop_names, atoms.utf8_string, 8,
                                Xc.PROP_MODE_REPLACE, (void*) names.data, (int) names.len);
        }

        uint wrap_desktop (int d) {
            int n = (int) n_desktops;
            return (uint) (((d % n) + n) % n);
        }

        void switch_desktop_relative (int step) {
            switch_desktop (wrap_desktop ((int) current_desktop + step));
        }

        void switch_desktop (uint d) {
            if (d >= n_desktops || d == current_desktop) {
                return;
            }
            if (cycling) {
                end_cycle (false);
            }
            if (drag != DragMode.NONE) {
                end_drag ();
            }
            /* Dirección del deslizamiento (picom lo lee de _FENSTER_ANIM) */
            var anim = d > current_desktop ? "desk-next" : "desk-prev";
            current_desktop = d;
            /* Primero mostrar las del nuevo escritorio y luego ocultar las del anterior:
             * evita ver el fondo vacío durante el cambio. */
            clients.foreach ((c) => {
                if (c.hidden_by_desktop && c.on_desktop (d)) {
                    c.hidden_by_desktop = false;
                    if (!c.minimized) {
                        set_anim (c, anim);
                        dpy.map_window (c.win);
                    }
                }
            });
            clients.foreach ((c) => {
                if (!c.hidden_by_desktop && !c.on_desktop (d)) {
                    c.hidden_by_desktop = true;
                    if (!c.minimized) {
                        set_anim (c, anim);
                        c.ignore_unmaps++;
                        dpy.unmap_window (c.win);
                    }
                }
            });
            set_prop (root, atoms.net_current_desktop, Xc.XA_CARDINAL, { (long) d });
            if (focused == null || !focused.can_focus ()) {
                focused = null;
                focus_next ();
            }
            restack ();
            update_client_lists ();
            debug ("escritorio %u", d + 1);
        }

        void move_to_desktop (Client c, uint d, bool follow) {
            if (c.kind.is_chrome () || (d >= n_desktops && d != ALL_DESKTOPS)) {
                return;
            }
            c.desktop = d;
            set_prop (c.win, atoms.net_wm_desktop, Xc.XA_CARDINAL, { (long) d });
            /* Sus diálogos le acompañan */
            clients.foreach ((t) => {
                if (t.transient_for == c.win && !t.kind.is_chrome ()) {
                    t.desktop = d;
                    set_prop (t.win, atoms.net_wm_desktop, Xc.XA_CARDINAL, { (long) d });
                }
            });
            if (follow && d != ALL_DESKTOPS) {
                switch_desktop (d);
                activate (c);
            } else {
                sync_visibility ();
            }
            update_net_wm_state (c);
        }

        /* Muestra/oculta cada ventana según el escritorio actual. */
        void sync_visibility () {
            clients.foreach ((c) => {
                bool should_hide = !c.on_desktop (current_desktop);
                if (should_hide && !c.hidden_by_desktop) {
                    c.hidden_by_desktop = true;
                    if (!c.minimized) {
                        c.ignore_unmaps++;
                        dpy.unmap_window (c.win);
                    }
                } else if (!should_hide && c.hidden_by_desktop) {
                    c.hidden_by_desktop = false;
                    if (!c.minimized) {
                        dpy.map_window (c.win);
                    }
                }
            });
            if (focused != null && !focused.can_focus ()) {
                focused = null;
                focus_next ();
            }
        }

        void set_desktop_count (uint n) {
            n = uint.max (1, uint.min (n, MAX_DESKTOPS));
            if (n == n_desktops) {
                return;
            }
            /* Ventanas de escritorios que desaparecen → al último que queda */
            clients.foreach ((c) => {
                if (!c.sticky () && c.desktop >= n) {
                    c.desktop = n - 1;
                    set_prop (c.win, atoms.net_wm_desktop, Xc.XA_CARDINAL, { (long) c.desktop });
                }
            });
            n_desktops = n;
            if (current_desktop >= n) {
                current_desktop = n - 1;
            }
            update_desktop_props ();
            update_workarea ();
            sync_visibility ();
        }

        /* ---------------------------------------------------------------- */
        /* Capas, modales, urgencia y robo de foco                           */
        /* ---------------------------------------------------------------- */

        /* Marca para picom: qué animación usar en el próximo mostrar/ocultar.
         * Se borra al terminar para que un cierre normal use la animación por defecto. */
        HashTable<Client, uint> anim_timers = new HashTable<Client, uint> (direct_hash, direct_equal);

        void set_anim (Client c, string kind) {
            Xx.change_property (dpy, c.win, atoms.fenster_anim, (X.Atom) 31 /* STRING */, 8,
                                Xc.PROP_MODE_REPLACE, (void*) kind.data, kind.length);
            uint old = anim_timers[c];
            if (old != 0) {
                Source.remove (old);
            }
            anim_timers[c] = Timeout.add (Style.GEOMETRY_MS + 200, () => {
                anim_timers.remove (c);
                if (find (c.win) != null) {
                    dpy.delete_property (c.win, atoms.fenster_anim);
                    dpy.flush ();
                }
                return Source.REMOVE;
            });
        }

        void set_above (Client c, bool on) {
            c.above = on;
            if (on) {
                c.below = false;
            }
            restack ();
            update_client_lists ();
            update_net_wm_state (c);
        }

        void set_urgent (Client c, bool on) {
            if (c.urgent == on) {
                return;
            }
            c.urgent = on;
            update_net_wm_state (c);
        }

        Client? modal_child (Client c) {
            for (int i = 0; i < clients.length; i++) {
                var t = clients[i];
                if (t.transient_for == c.win && t.modal && !t.minimized && !t.hidden_by_desktop) {
                    return t;
                }
            }
            return null;
        }

        void read_user_time_window (Client c) {
            var v = get_longs (c.win, atoms.net_wm_user_time_window, Xc.XA_WINDOW, 1);
            if (v.length > 0 && v[0] != 0) {
                c.user_time_win = (X.Window) v[0];
                dpy.select_input (c.user_time_win, (long) Xc.PROPERTY_CHANGE_MASK);
            }
        }

        void read_user_time (Client c) {
            var src = c.user_time_win != 0 ? c.user_time_win : c.win;
            var v = get_longs (src, atoms.net_wm_user_time, Xc.XA_CARDINAL, 1);
            if (v.length > 0) {
                c.has_user_time = true;
                c.user_time = (ulong) v[0] & 0xFFFFFFFF;
            }
        }

        /* Tiempo X de 32 bits con desbordamiento: ¿a ocurrió antes que b? */
        static bool time_before (ulong a, ulong b) {
            return a != b && ((b - a) & 0xFFFFFFFF) < 0x80000000;
        }

        /* ¿Debe una ventana recién mapeada tomar el foco? (EWMH _NET_WM_USER_TIME) */
        bool should_focus_new (Client c) {
            if (focused == null) return true;
            if (c.transient_for == focused.win) return true;         /* diálogo de la activa */
            if (c.has_user_time && c.user_time == 0) return false;   /* la app pide no enfocar */
            if (c.has_user_time && focused.has_user_time
                && time_before (c.user_time, focused.user_time)) {
                return false;  /* el usuario siguió usando la ventana activa */
            }
            return true;
        }

        /* Petición de activación hecha por la propia app (fuente 1). */
        bool allow_activation (Client c, ulong timestamp) {
            if (focused == null || focused == c || timestamp == 0) return true;
            if (c.transient_for == focused.win || focused.transient_for == c.win) return true;
            if (focused.has_user_time && time_before (timestamp & 0xFFFFFFFF, focused.user_time)) {
                return false;
            }
            return true;
        }

        void update_client_lists () {
            long[] list = {};
            clients.foreach ((c) => { list += (long) c.win; });
            set_prop (root, atoms.net_client_list, Xc.XA_WINDOW, list);
            long[] stack = {};
            stacking.foreach ((c) => { stack += (long) c.win; });
            set_prop (root, atoms.net_client_list_stacking, Xc.XA_WINDOW, stack);
        }

        void update_net_wm_state (Client c) {
            long[] st = {};
            if (c.fullscreen) st += (long) atoms.net_wm_state_fullscreen;
            if (c.maximized) {
                st += (long) atoms.net_wm_state_maximized_vert;
                st += (long) atoms.net_wm_state_maximized_horz;
            }
            if (c.minimized) st += (long) atoms.net_wm_state_hidden;
            if (c.above) st += (long) atoms.net_wm_state_above;
            if (c.below) st += (long) atoms.net_wm_state_below;
            if (c.sticky () && !c.kind.is_chrome ()) st += (long) atoms.net_wm_state_sticky;
            if (c.skip_taskbar) st += (long) atoms.net_wm_state_skip_taskbar;
            if (c.skip_pager) st += (long) atoms.net_wm_state_skip_pager;
            if (c.modal) st += (long) atoms.net_wm_state_modal;
            if (c.urgent) st += (long) atoms.net_wm_state_demands_attention;
            set_prop (c.win, atoms.net_wm_state, Xc.XA_ATOM, st);
        }

        void set_wm_state (Client c, long state) {
            set_prop (c.win, atoms.wm_state, atoms.wm_state, { state, 0 });
        }

        void send_protocol (Client c, X.Atom proto) {
            var ev = X.Event ();
            ev.xclient.type = Xc.CLIENT_MESSAGE;
            ev.xclient.window = c.win;
            ev.xclient.message_type = atoms.wm_protocols;
            ev.xclient.format = 32;
            ev.xclient.l[0] = (long) proto;
            ev.xclient.l[1] = Xc.CURRENT_TIME;
            Xx.send_event (dpy, c.win, false, 0, &ev);
        }
    }
}
