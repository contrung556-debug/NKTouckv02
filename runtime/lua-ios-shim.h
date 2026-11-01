// NKTouch Lua process shim for jailbroken iOS.
// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef NKTOUCH_LUA_IOS_SHIM_H
#define NKTOUCH_LUA_IOS_SHIM_H

#include <stdio.h>

int nktouch_lua_system(const char *cmd);
FILE *nktouch_lua_popen(void *lua_state, const char *cmd, const char *mode);
int nktouch_lua_pclose(void *lua_state, FILE *stream);

#endif
