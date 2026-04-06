#pragma once

#include <stdint.h>

#define WWN_KEY_LEFTSHIFT 42u

uint32_t android_keycode_to_linux(uint32_t android_keycode);
uint32_t char_to_linux_keycode(char ch, int *needs_shift);
