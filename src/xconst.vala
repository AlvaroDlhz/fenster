/* Constantes de X11 en forma numérica: más explícito que los enums de x11.vapi. */
namespace Fenster.Xc {
    /* Máscaras de eventos */
    public const long KEY_PRESS_MASK = 1L << 0;
    public const long BUTTON_PRESS_MASK = 1L << 2;
    public const long BUTTON_RELEASE_MASK = 1L << 3;
    public const long ENTER_WINDOW_MASK = 1L << 4;
    public const long POINTER_MOTION_MASK = 1L << 6;
    public const long STRUCTURE_NOTIFY_MASK = 1L << 17;
    public const long SUBSTRUCTURE_NOTIFY_MASK = 1L << 19;
    public const long SUBSTRUCTURE_REDIRECT_MASK = 1L << 20;
    public const long FOCUS_CHANGE_MASK = 1L << 21;
    public const long PROPERTY_CHANGE_MASK = 1L << 22;

    /* Tipos de evento */
    public const int KEY_PRESS = 2;
    public const int BUTTON_PRESS = 4;
    public const int BUTTON_RELEASE = 5;
    public const int MOTION_NOTIFY = 6;
    public const int DESTROY_NOTIFY = 17;
    public const int UNMAP_NOTIFY = 18;
    public const int MAP_REQUEST = 20;
    public const int CONFIGURE_REQUEST = 23;
    public const int PROPERTY_NOTIFY = 28;
    public const int CLIENT_MESSAGE = 33;
    public const int MAPPING_NOTIFY = 34;

    /* Modificadores */
    public const uint SHIFT = 1 << 0;
    public const uint LOCK = 1 << 1;
    public const uint CONTROL = 1 << 2;
    public const uint MOD1 = 1 << 3; /* Alt */
    public const uint MOD2 = 1 << 4; /* Bloq Num */
    public const uint MOD4 = 1 << 6; /* Super */
    public const uint ANY_MODIFIER = 1 << 15;

    /* Grabs y foco */
    public const int GRAB_MODE_SYNC = 0;
    public const int GRAB_MODE_ASYNC = 1;
    public const int REPLAY_POINTER = 2;
    public const uint ANY_BUTTON = 0;
    public const int REVERT_TO_POINTER_ROOT = 1;
    public const int CURRENT_TIME = 0;
    public const int PROP_MODE_REPLACE = 0;

    /* ConfigureRequest value_mask */
    public const ulong CW_X = 1 << 0;
    public const ulong CW_Y = 1 << 1;
    public const ulong CW_WIDTH = 1 << 2;
    public const ulong CW_HEIGHT = 1 << 3;
    public const ulong CW_BORDER_WIDTH = 1 << 4;
    public const ulong CW_SIBLING = 1 << 5;
    public const ulong CW_STACK_MODE = 1 << 6;

    /* ICCCM WM_STATE */
    public const long WITHDRAWN_STATE = 0;
    public const long NORMAL_STATE = 1;
    public const long ICONIC_STATE = 3;

    /* Errores */
    public const uchar BAD_ACCESS = 10;

    /* Keysyms */
    public const ulong XK_TAB = 0xff09;
    public const ulong XK_RETURN = 0xff0d;
    public const ulong XK_LEFT = 0xff51;
    public const ulong XK_UP = 0xff52;
    public const ulong XK_RIGHT = 0xff53;
    public const ulong XK_DOWN = 0xff54;
    public const ulong XK_F4 = 0xffc1;
    public const ulong XK_1 = 0x31;
    public const ulong XK_9 = 0x39;
    public const ulong XK_T = 0x74;
    public const ulong XK_GRAVE = 0x60;
    public const ulong XK_ESCAPE = 0xff1b;

    /* Cursores (X11/cursorfont.h) */
    public const uint XC_LEFT_PTR = 68;
    public const uint XC_FLEUR = 52;
    public const uint XC_BOTTOM_RIGHT_CORNER = 14;

    /* Tipos de atom predefinidos */
    public const ulong XA_ATOM = 4;
    public const ulong XA_CARDINAL = 6;
    public const ulong XA_WINDOW = 33;
}
