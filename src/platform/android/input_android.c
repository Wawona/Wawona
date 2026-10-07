/**
 * Android input helpers - keycode mapping and modifier tracking
 *
 * Maps Android KeyEvent keycodes to Linux evdev/XKB keycodes.
 * Android keycodes are similar but not identical to Linux.
 */

#include "input_android.h"
#include "../cproof/wawona_cproof.h"
#include <stdint.h>

/* Linux evdev key codes (from input-event-codes.h) */
#define KEY_RESERVED        0
#define KEY_ESC             1
#define KEY_1               2
#define KEY_2               3
#define KEY_3               4
#define KEY_4               5
#define KEY_5               6
#define KEY_6               7
#define KEY_7               8
#define KEY_8               9
#define KEY_9               10
#define KEY_0               11
#define KEY_MINUS           12
#define KEY_EQUAL           13
#define KEY_BACKSPACE       14
#define KEY_TAB             15
#define KEY_Q               16
#define KEY_W               17
#define KEY_E               18
#define KEY_R               19
#define KEY_T               20
#define KEY_Y               21
#define KEY_U               22
#define KEY_I               23
#define KEY_O               24
#define KEY_P               25
#define KEY_LEFTBRACE       26
#define KEY_RIGHTBRACE      27
#define KEY_ENTER           28
#define KEY_LEFTCTRL        29
#define KEY_A               30
#define KEY_S               31
#define KEY_D               32
#define KEY_F               33
#define KEY_G               34
#define KEY_H               35
#define KEY_J               36
#define KEY_K               37
#define KEY_L               38
#define KEY_SEMICOLON       39
#define KEY_APOSTROPHE      40
#define KEY_GRAVE           41
#define KEY_LEFTSHIFT       42
#define KEY_BACKSLASH       43
#define KEY_Z               44
#define KEY_X               45
#define KEY_C               46
#define KEY_V               47
#define KEY_B               48
#define KEY_N               49
#define KEY_M               50
#define KEY_COMMA           51
#define KEY_DOT             52
#define KEY_SLASH           53
#define KEY_RIGHTSHIFT      54
#define KEY_LEFTALT         56
#define KEY_SPACE           57
#define KEY_RIGHTALT        100
#define KEY_RIGHTCTRL       97
#define KEY_LEFTMETA        125
#define KEY_RIGHTMETA       126
#define KEY_DELETE          111
#define KEY_FORWARD_DEL     119
#define KEY_HOME            102
#define KEY_END             107
#define KEY_INSERT          110
#define KEY_PAGEUP          104
#define KEY_PAGEDOWN        109
#define KEY_UP              103
#define KEY_DOWN            108
#define KEY_LEFT            105
#define KEY_RIGHT           106

/* Android KeyEvent keycodes - same values as in android/view/KeyEvent.java */
#define AKEYCODE_SOFT_LEFT       1
#define AKEYCODE_SOFT_RIGHT     2
#define AKEYCODE_HOME           3
#define AKEYCODE_BACK           4
#define AKEYCODE_CALL           5
#define AKEYCODE_ENDCALL        6
#define AKEYCODE_0              7
#define AKEYCODE_1              8
#define AKEYCODE_2              9
#define AKEYCODE_3              10
#define AKEYCODE_4              11
#define AKEYCODE_5              12
#define AKEYCODE_6              13
#define AKEYCODE_7              14
#define AKEYCODE_8              15
#define AKEYCODE_9              16
#define AKEYCODE_STAR           17
#define AKEYCODE_POUND          18
#define AKEYCODE_DPAD_UP        19
#define AKEYCODE_DPAD_DOWN      20
#define AKEYCODE_DPAD_LEFT      21
#define AKEYCODE_DPAD_RIGHT     22
#define AKEYCODE_DPAD_CENTER    23
#define AKEYCODE_VOLUME_UP      24
#define AKEYCODE_VOLUME_DOWN    25
#define AKEYCODE_POWER          26
#define AKEYCODE_CAMERA         27
#define AKEYCODE_CLEAR          28
#define AKEYCODE_A              29
#define AKEYCODE_B              30
#define AKEYCODE_C              31
#define AKEYCODE_D              32
#define AKEYCODE_E              33
#define AKEYCODE_F              34
#define AKEYCODE_G              35
#define AKEYCODE_H              36
#define AKEYCODE_I              37
#define AKEYCODE_J              38
#define AKEYCODE_K              39
#define AKEYCODE_L              40
#define AKEYCODE_M              41
#define AKEYCODE_N              42
#define AKEYCODE_O              43
#define AKEYCODE_P              44
#define AKEYCODE_Q              45
#define AKEYCODE_R              46
#define AKEYCODE_S              47
#define AKEYCODE_T              48
#define AKEYCODE_U              49
#define AKEYCODE_V              50
#define AKEYCODE_W              51
#define AKEYCODE_X              52
#define AKEYCODE_Y              53
#define AKEYCODE_Z              54
#define AKEYCODE_COMMA          55
#define AKEYCODE_PERIOD         56
#define AKEYCODE_ALT_LEFT       57
#define AKEYCODE_ALT_RIGHT      58
#define AKEYCODE_SHIFT_LEFT     59
#define AKEYCODE_SHIFT_RIGHT    60
#define AKEYCODE_TAB            61
#define AKEYCODE_SPACE          62
#define AKEYCODE_SYMBOL         63
#define AKEYCODE_EXPLORER       64
#define AKEYCODE_ENVELOPE       65
#define AKEYCODE_ENTER          66
#define AKEYCODE_DEL            67
#define AKEYCODE_GRAVE          68
#define AKEYCODE_MINUS          69
#define AKEYCODE_EQUALS         70
#define AKEYCODE_LEFT_BRACKET   71
#define AKEYCODE_RIGHT_BRACKET  72
#define AKEYCODE_BACKSLASH      73
#define AKEYCODE_SEMICOLON      74
#define AKEYCODE_APOSTROPHE     75
#define AKEYCODE_SLASH          76
#define AKEYCODE_AT             77
#define AKEYCODE_NUM            78
#define AKEYCODE_HEADPHONEHOOK  79
#define AKEYCODE_FOCUS          80
#define AKEYCODE_PLUS           81
#define AKEYCODE_MENU           82
#define AKEYCODE_NOTIFICATION   83
#define AKEYCODE_SEARCH         84
#define AKEYCODE_DPAD_UP_2      85
#define AKEYCODE_DPAD_DOWN_2    86
#define AKEYCODE_DPAD_LEFT_2    87
#define AKEYCODE_DPAD_RIGHT_2   88
#define AKEYCODE_DPAD_CENTER_2  89
#define AKEYCODE_CTRL_LEFT      113
#define AKEYCODE_CTRL_RIGHT     114
#define AKEYCODE_ESCAPE         111
#define AKEYCODE_FORWARD_DEL    112
#define AKEYCODE_META_LEFT      117
#define AKEYCODE_META_RIGHT     118

uint32_t android_keycode_to_linux(uint32_t android_keycode) {
    uint32_t code;
    switch (android_keycode) {
    case AKEYCODE_A: code = KEY_A; break;
    case AKEYCODE_B: code = KEY_B; break;
    case AKEYCODE_C: code = KEY_C; break;
    case AKEYCODE_D: code = KEY_D; break;
    case AKEYCODE_E: code = KEY_E; break;
    case AKEYCODE_F: code = KEY_F; break;
    case AKEYCODE_G: code = KEY_G; break;
    case AKEYCODE_H: code = KEY_H; break;
    case AKEYCODE_I: code = KEY_I; break;
    case AKEYCODE_J: code = KEY_J; break;
    case AKEYCODE_K: code = KEY_K; break;
    case AKEYCODE_L: code = KEY_L; break;
    case AKEYCODE_M: code = KEY_M; break;
    case AKEYCODE_N: code = KEY_N; break;
    case AKEYCODE_O: code = KEY_O; break;
    case AKEYCODE_P: code = KEY_P; break;
    case AKEYCODE_Q: code = KEY_Q; break;
    case AKEYCODE_R: code = KEY_R; break;
    case AKEYCODE_S: code = KEY_S; break;
    case AKEYCODE_T: code = KEY_T; break;
    case AKEYCODE_U: code = KEY_U; break;
    case AKEYCODE_V: code = KEY_V; break;
    case AKEYCODE_W: code = KEY_W; break;
    case AKEYCODE_X: code = KEY_X; break;
    case AKEYCODE_Y: code = KEY_Y; break;
    case AKEYCODE_Z: code = KEY_Z; break;
    case AKEYCODE_0: code = KEY_0; break;
    case AKEYCODE_1: code = KEY_1; break;
    case AKEYCODE_2: code = KEY_2; break;
    case AKEYCODE_3: code = KEY_3; break;
    case AKEYCODE_4: code = KEY_4; break;
    case AKEYCODE_5: code = KEY_5; break;
    case AKEYCODE_6: code = KEY_6; break;
    case AKEYCODE_7: code = KEY_7; break;
    case AKEYCODE_8: code = KEY_8; break;
    case AKEYCODE_9: code = KEY_9; break;
    case AKEYCODE_CTRL_LEFT:  code = KEY_LEFTCTRL; break;
    case AKEYCODE_CTRL_RIGHT: code = KEY_RIGHTCTRL; break;
    case AKEYCODE_SHIFT_LEFT: code = KEY_LEFTSHIFT; break;
    case AKEYCODE_SHIFT_RIGHT: code = KEY_RIGHTSHIFT; break;
    case AKEYCODE_ALT_LEFT:   code = KEY_LEFTALT; break;
    case AKEYCODE_ALT_RIGHT:  code = KEY_RIGHTALT; break;
    case AKEYCODE_META_LEFT:  code = KEY_LEFTMETA; break;
    case AKEYCODE_META_RIGHT: code = KEY_RIGHTMETA; break;
    case AKEYCODE_DPAD_UP:
    case AKEYCODE_DPAD_UP_2:  code = KEY_UP; break;
    case AKEYCODE_DPAD_DOWN:
    case AKEYCODE_DPAD_DOWN_2: code = KEY_DOWN; break;
    case AKEYCODE_DPAD_LEFT:
    case AKEYCODE_DPAD_LEFT_2: code = KEY_LEFT; break;
    case AKEYCODE_DPAD_RIGHT:
    case AKEYCODE_DPAD_RIGHT_2: code = KEY_RIGHT; break;
    case AKEYCODE_ENTER:
    case AKEYCODE_DPAD_CENTER:
    case AKEYCODE_DPAD_CENTER_2: code = KEY_ENTER; break;
    case AKEYCODE_TAB:  code = KEY_TAB; break;
    case AKEYCODE_SPACE: code = KEY_SPACE; break;
    case AKEYCODE_ESCAPE: code = KEY_ESC; break;
    case AKEYCODE_DEL: code = KEY_BACKSPACE; break;
    case AKEYCODE_FORWARD_DEL: code = KEY_DELETE; break;
    case AKEYCODE_HOME: code = KEY_HOME; break;
    case AKEYCODE_ENDCALL: code = KEY_END; break;
    case AKEYCODE_COMMA: code = KEY_COMMA; break;
    case AKEYCODE_PERIOD: code = KEY_DOT; break;
    case AKEYCODE_SLASH: code = KEY_SLASH; break;
    case AKEYCODE_MINUS: code = KEY_MINUS; break;
    case AKEYCODE_EQUALS: code = KEY_EQUAL; break;
    case AKEYCODE_LEFT_BRACKET: code = KEY_LEFTBRACE; break;
    case AKEYCODE_RIGHT_BRACKET: code = KEY_RIGHTBRACE; break;
    case AKEYCODE_BACKSLASH: code = KEY_BACKSLASH; break;
    case AKEYCODE_SEMICOLON: code = KEY_SEMICOLON; break;
    case AKEYCODE_APOSTROPHE: code = KEY_APOSTROPHE; break;
    case AKEYCODE_GRAVE: code = KEY_GRAVE; break;
    default: code = KEY_RESERVED; break;
    }
    if (!wawona_linux_keycode_ok(code)) {
        return KEY_RESERVED;
    }
    return code;
}

uint32_t control_to_linux_keycode(char ch, int *needs_shift) {
    /* Terminal fallback only. Printable text is TI v3 (host-keymap-bridge). */
    if (needs_shift != NULL) {
        *needs_shift = 0;
    }
    switch (ch) {
    case '\n':
    case '\r':
        return KEY_ENTER;
    case '\t':
        return KEY_TAB;
    case 0x08:
    case 0x7f:
        return KEY_BACKSPACE;
    default:
        return 0;
    }
}
