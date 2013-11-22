/* Copyright 2012-2013 Nils Nordman <nino at nordman.org> */
/* License: MIT (see LICENSE) */

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>

#include <glib.h>
#include <gtk/gtk.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

/* External dependencies hookups */
int luaopen_lpeg (lua_State *L);
int luaopen_lfs (lua_State *L);
int luaopen_lgi_corelgilua51 (lua_State* L);
