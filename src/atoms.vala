namespace Fenster {
    /* Atoms de ICCCM y EWMH que usa Fenster. */
    public class Atoms {
        public X.Atom wm_protocols;
        public X.Atom wm_delete_window;
        public X.Atom wm_take_focus;
        public X.Atom wm_state;
        public X.Atom wm_change_state;
        public X.Atom utf8_string;

        public X.Atom net_supported;
        public X.Atom net_supporting_wm_check;
        public X.Atom net_wm_name;
        public X.Atom net_client_list;
        public X.Atom net_client_list_stacking;
        public X.Atom net_active_window;
        public X.Atom net_close_window;
        public X.Atom net_number_of_desktops;
        public X.Atom net_current_desktop;
        public X.Atom net_desktop_names;
        public X.Atom net_wm_desktop;
        public X.Atom net_workarea;
        public X.Atom net_frame_extents;
        public X.Atom net_request_frame_extents;
        public X.Atom net_wm_moveresize;
        public X.Atom net_wm_strut;
        public X.Atom net_wm_strut_partial;

        public X.Atom net_wm_state;
        public X.Atom net_wm_state_fullscreen;
        public X.Atom net_wm_state_maximized_vert;
        public X.Atom net_wm_state_maximized_horz;
        public X.Atom net_wm_state_hidden;
        public X.Atom net_wm_state_above;
        public X.Atom net_wm_state_skip_taskbar;

        public X.Atom net_wm_window_type;
        public X.Atom net_wm_window_type_desktop;
        public X.Atom net_wm_window_type_dock;
        public X.Atom net_wm_window_type_dialog;
        public X.Atom net_wm_window_type_utility;
        public X.Atom net_wm_window_type_splash;
        public X.Atom net_wm_window_type_normal;

        public X.Atom gtk_frame_extents;

        public X.Atom wm_hints;
        public X.Atom wm_class;
        public X.Atom net_wm_icon;
        public X.Atom fenster_anim;
        public X.Atom net_wm_window_opacity;
        public X.Atom wm_normal_hints;
        public X.Atom net_desktop_viewport;
        public X.Atom net_desktop_geometry;
        public X.Atom net_wm_user_time;
        public X.Atom net_wm_user_time_window;
        public X.Atom net_wm_state_below;
        public X.Atom net_wm_state_sticky;
        public X.Atom net_wm_state_skip_pager;
        public X.Atom net_wm_state_modal;
        public X.Atom net_wm_state_demands_attention;

        public Atoms (X.Display d) {
            wm_protocols = d.intern_atom ("WM_PROTOCOLS", false);
            wm_delete_window = d.intern_atom ("WM_DELETE_WINDOW", false);
            wm_take_focus = d.intern_atom ("WM_TAKE_FOCUS", false);
            wm_state = d.intern_atom ("WM_STATE", false);
            wm_change_state = d.intern_atom ("WM_CHANGE_STATE", false);
            utf8_string = d.intern_atom ("UTF8_STRING", false);

            net_supported = d.intern_atom ("_NET_SUPPORTED", false);
            net_supporting_wm_check = d.intern_atom ("_NET_SUPPORTING_WM_CHECK", false);
            net_wm_name = d.intern_atom ("_NET_WM_NAME", false);
            net_client_list = d.intern_atom ("_NET_CLIENT_LIST", false);
            net_client_list_stacking = d.intern_atom ("_NET_CLIENT_LIST_STACKING", false);
            net_active_window = d.intern_atom ("_NET_ACTIVE_WINDOW", false);
            net_close_window = d.intern_atom ("_NET_CLOSE_WINDOW", false);
            net_number_of_desktops = d.intern_atom ("_NET_NUMBER_OF_DESKTOPS", false);
            net_current_desktop = d.intern_atom ("_NET_CURRENT_DESKTOP", false);
            net_desktop_names = d.intern_atom ("_NET_DESKTOP_NAMES", false);
            net_wm_desktop = d.intern_atom ("_NET_WM_DESKTOP", false);
            net_workarea = d.intern_atom ("_NET_WORKAREA", false);
            net_frame_extents = d.intern_atom ("_NET_FRAME_EXTENTS", false);
            net_request_frame_extents = d.intern_atom ("_NET_REQUEST_FRAME_EXTENTS", false);
            net_wm_moveresize = d.intern_atom ("_NET_WM_MOVERESIZE", false);
            net_wm_strut = d.intern_atom ("_NET_WM_STRUT", false);
            net_wm_strut_partial = d.intern_atom ("_NET_WM_STRUT_PARTIAL", false);

            net_wm_state = d.intern_atom ("_NET_WM_STATE", false);
            net_wm_state_fullscreen = d.intern_atom ("_NET_WM_STATE_FULLSCREEN", false);
            net_wm_state_maximized_vert = d.intern_atom ("_NET_WM_STATE_MAXIMIZED_VERT", false);
            net_wm_state_maximized_horz = d.intern_atom ("_NET_WM_STATE_MAXIMIZED_HORZ", false);
            net_wm_state_hidden = d.intern_atom ("_NET_WM_STATE_HIDDEN", false);
            net_wm_state_above = d.intern_atom ("_NET_WM_STATE_ABOVE", false);
            net_wm_state_skip_taskbar = d.intern_atom ("_NET_WM_STATE_SKIP_TASKBAR", false);

            net_wm_window_type = d.intern_atom ("_NET_WM_WINDOW_TYPE", false);
            net_wm_window_type_desktop = d.intern_atom ("_NET_WM_WINDOW_TYPE_DESKTOP", false);
            net_wm_window_type_dock = d.intern_atom ("_NET_WM_WINDOW_TYPE_DOCK", false);
            net_wm_window_type_dialog = d.intern_atom ("_NET_WM_WINDOW_TYPE_DIALOG", false);
            net_wm_window_type_utility = d.intern_atom ("_NET_WM_WINDOW_TYPE_UTILITY", false);
            net_wm_window_type_splash = d.intern_atom ("_NET_WM_WINDOW_TYPE_SPLASH", false);
            net_wm_window_type_normal = d.intern_atom ("_NET_WM_WINDOW_TYPE_NORMAL", false);

            gtk_frame_extents = d.intern_atom ("_GTK_FRAME_EXTENTS", false);

            wm_hints = d.intern_atom ("WM_HINTS", false);
            wm_class = d.intern_atom ("WM_CLASS", false);
            net_wm_icon = d.intern_atom ("_NET_WM_ICON", false);
            fenster_anim = d.intern_atom ("_FENSTER_ANIM", false);
            net_wm_window_opacity = d.intern_atom ("_NET_WM_WINDOW_OPACITY", false);
            wm_normal_hints = d.intern_atom ("WM_NORMAL_HINTS", false);
            net_desktop_viewport = d.intern_atom ("_NET_DESKTOP_VIEWPORT", false);
            net_desktop_geometry = d.intern_atom ("_NET_DESKTOP_GEOMETRY", false);
            net_wm_user_time = d.intern_atom ("_NET_WM_USER_TIME", false);
            net_wm_user_time_window = d.intern_atom ("_NET_WM_USER_TIME_WINDOW", false);
            net_wm_state_below = d.intern_atom ("_NET_WM_STATE_BELOW", false);
            net_wm_state_sticky = d.intern_atom ("_NET_WM_STATE_STICKY", false);
            net_wm_state_skip_pager = d.intern_atom ("_NET_WM_STATE_SKIP_PAGER", false);
            net_wm_state_modal = d.intern_atom ("_NET_WM_STATE_MODAL", false);
            net_wm_state_demands_attention = d.intern_atom ("_NET_WM_STATE_DEMANDS_ATTENTION", false);
        }

        /* Lo que anunciamos en _NET_SUPPORTED. */
        public X.Atom[] supported () {
            return {
                net_supported, net_supporting_wm_check, net_wm_name,
                net_client_list, net_client_list_stacking, net_active_window,
                net_close_window, net_number_of_desktops, net_current_desktop,
                net_desktop_names, net_wm_desktop, net_workarea,
                net_frame_extents, net_request_frame_extents, net_wm_moveresize,
                net_wm_strut, net_wm_strut_partial,
                net_wm_state, net_wm_state_fullscreen, net_wm_state_maximized_vert,
                net_wm_state_maximized_horz, net_wm_state_hidden,
                net_wm_state_above, net_wm_state_below, net_wm_state_sticky,
                net_wm_state_skip_taskbar, net_wm_state_skip_pager,
                net_wm_state_modal, net_wm_state_demands_attention,
                net_desktop_viewport, net_desktop_geometry,
                net_wm_user_time, net_wm_user_time_window,
                net_wm_window_type, net_wm_window_type_desktop, net_wm_window_type_dock,
                net_wm_window_type_dialog, net_wm_window_type_utility,
                net_wm_window_type_splash, net_wm_window_type_normal
            };
        }
    }
}
