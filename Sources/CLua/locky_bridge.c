#include "locky_bridge.h"

#include <stdio.h>
#include <stdlib.h>
#include <time.h>

double locky_now(void) {
    return (double)clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1e9;
}

LockyGuard *locky_guard(lua_State *L) {
    void *ud = NULL;
    lua_getallocf(L, &ud);
    return (LockyGuard *)ud;
}

/* Counts every byte. Past the soft limit it only raises a flag: failing there could raise an error inside
 * a host call, outside any protected call. The hook turns the flag into an error inside Lua code. */
static void *locky_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
    LockyGuard *g = (LockyGuard *)ud;
    size_t old = ptr ? osize : 0; /* without ptr, osize names the kind of object, not a size */
    if (nsize == 0) {
        free(ptr);
        g->used -= old;
        return NULL;
    }
    if (nsize > old && g->hard_limit > 0 && g->used - old + nsize > g->hard_limit) {
        return NULL;
    }
    void *block = realloc(ptr, nsize);
    if (block == NULL) {
        return NULL;
    }
    g->used = g->used - old + nsize;
    if (g->used > g->peak) {
        g->peak = g->used;
    }
    if (g->soft_limit > 0 && g->used > g->soft_limit) {
        g->over_soft = 1;
    }
    return block;
}

#define LOCKY_TIMEOUT "time budget exceeded: Locky stopped code that ran too long"
#define LOCKY_NO_MEMORY "not enough memory: Locky stopped code that used too much"

static void locky_hook(lua_State *L, lua_Debug *ar) {
    (void)ar;
    LockyGuard *g = locky_guard(L);
    if (g->over_soft) {
        g->over_soft = 0;
        lua_gc(L, LUA_GCCOLLECT);
        if (g->used > g->soft_limit) {
            g->over_soft = 1;
            g->memory_error = 1;
            luaL_error(L, "not enough memory: plugins may use %d MB in all", (int)(g->soft_limit >> 20));
        }
    }
    if (g->deadline > 0 && (g->timed_out || locky_now() > g->deadline)) {
        g->timed_out = 1;
        luaL_error(L, LOCKY_TIMEOUT);
    }
}

static int locky_panic(lua_State *L) {
    /* Only an error outside every protected call reaches here, which Locky never makes. Lua aborts next. */
    const char *message = lua_tostring(L, -1);
    fprintf(stderr, "Locky: unprotected Lua error: %s\n", message ? message : "(no message)");
    return 0;
}

lua_State *locky_newstate(LockyGuard *guard) {
    lua_State *L = lua_newstate(locky_alloc, guard, arc4random()); /* the seed randomizes string hashing */
    if (L == NULL) {
        return NULL;
    }
    lua_atpanic(L, locky_panic);
    lua_sethook(L, locky_hook, LUA_MASKCOUNT, 1000); /* new coroutines copy the hook */
    return L;
}

static void locky_drop(lua_State *L, const char *library, const char *name) {
    if (lua_getglobal(L, library) == LUA_TTABLE) {
        lua_pushnil(L);
        lua_setfield(L, -2, name);
    }
    lua_pop(L, 1);
}

void locky_openlibs(lua_State *L) {
    luaL_openlibs(L);

    locky_drop(L, "os", "exit");       /* would end the lock screen */
    locky_drop(L, "os", "execute");    /* blocks; plugins use locky.system */
    locky_drop(L, "io", "popen");      /* blocks; plugins use locky.system */
    locky_drop(L, "string", "dump");   /* bytecode; Locky loads source only */
    locky_drop(L, "package", "loadlib");

    /* No C modules: native code could crash the lock screen, and no hook can stop it. */
    if (lua_getglobal(L, "package") == LUA_TTABLE) {
        lua_pushliteral(L, "");
        lua_setfield(L, -2, "cpath");
        lua_pushliteral(L, "");
        lua_setfield(L, -2, "path");
        /* Keep only the preload searcher; the prelude adds Locky's runtime-path searcher. */
        lua_createtable(L, 2, 0);
        if (lua_getfield(L, -2, "searchers") == LUA_TTABLE) {
            lua_rawgeti(L, -1, 1);
            lua_rawseti(L, -3, 1);
        }
        lua_pop(L, 1);
        lua_setfield(L, -2, "searchers");
    }
    lua_pop(L, 1);

    /* File handles: no finalizer may be added to their metatable, since finalizers run with the time budget
     * off (getmetatable(io.stdout) returns false). */
    if (luaL_getmetatable(L, LUA_FILEHANDLE) == LUA_TTABLE) {
        lua_pushboolean(L, 0);
        lua_setfield(L, -2, "__metatable");
    }
    lua_pop(L, 1);

    /* debug: traceback and getinfo only. sethook would switch off the time budget. */
    if (lua_getglobal(L, "debug") == LUA_TTABLE) {
        lua_createtable(L, 0, 2);
        lua_getfield(L, -2, "traceback");
        lua_setfield(L, -2, "traceback");
        lua_getfield(L, -2, "getinfo");
        lua_setfield(L, -2, "getinfo");
        lua_pushvalue(L, -1);
        lua_setglobal(L, "debug");
        luaL_getsubtable(L, LUA_REGISTRYINDEX, LUA_LOADED_TABLE);
        lua_pushvalue(L, -2);
        lua_setfield(L, -2, "debug");
        lua_pop(L, 2);
    }
    lua_pop(L, 1);
}

static int locky_trampoline(lua_State *L) {
    LockyGuard *g = locky_guard(L);
    int index = (int)lua_tointeger(L, lua_upvalueindex(1));
    int results = g->dispatch(L, g->context, index);
    if (results < 0) {
        /* Prefix "file:line:" of the Lua code that made the call, like luaL_error. */
        luaL_where(L, 1);
        lua_insert(L, -2);
        lua_concat(L, 2);
        return lua_error(L);
    }
    return results;
}

void locky_pushnative(lua_State *L, int index) {
    lua_pushinteger(L, index);
    lua_pushcclosure(L, locky_trampoline, 1);
}

/* The message handler. It runs no Lua code: an error object's __tostring could loop past the budget. */
static int locky_traceback(lua_State *L) {
    const char *message = lua_tostring(L, 1);
    if (message == NULL) {
        message = lua_pushfstring(L, "(error object is a %s value)", luaL_typename(L, 1));
    }
    luaL_traceback(L, L, message, 1);
    return 1;
}

int locky_pcall(lua_State *L, int nargs, int nresults, double budget) {
    LockyGuard *g = locky_guard(L);
    double outer_deadline = g->deadline;
    int outer_timed_out = g->timed_out;
    int outer_memory_error = g->memory_error;

    double deadline = budget > 0 ? locky_now() + budget : 0;
    if (outer_deadline > 0 && (deadline == 0 || outer_deadline < deadline)) {
        deadline = outer_deadline;
    }
    g->deadline = deadline;
    g->timed_out = outer_timed_out;
    g->memory_error = 0;

    int base = lua_gettop(L) - nargs;
    lua_pushcfunction(L, locky_traceback);
    lua_insert(L, base);
    int status = lua_pcall(L, nargs, nresults, base);
    lua_remove(L, base);

    /* The count hook runs only between Lua instructions, so a long C function (table.move, a slow
     * pattern match) can finish past the deadline and return normally. Such a call still failed. */
    if (status == LUA_OK && deadline > 0 && locky_now() > deadline) {
        lua_settop(L, base - 1);
        size_t hard = g->hard_limit;
        g->hard_limit = 0;  /* the message must not fail to allocate outside a protected call */
        lua_pushliteral(L, LOCKY_TIMEOUT);
        g->hard_limit = hard;
        status = LUA_ERRRUN;
    }

    g->deadline = outer_deadline;
    g->timed_out = outer_timed_out;
    g->memory_error = outer_memory_error;
    return status;
}

int locky_loadbuffer(lua_State *L, const char *source, size_t length, const char *chunkname) {
    return luaL_loadbufferx(L, source, length, chunkname, "t");
}

int locky_budget_exceeded(lua_State *L) {
    LockyGuard *g = locky_guard(L);
    if (g->timed_out || (g->deadline > 0 && locky_now() > g->deadline)) {
        lua_pushliteral(L, LOCKY_TIMEOUT);
    } else if (g->memory_error) {
        lua_pushliteral(L, LOCKY_NO_MEMORY);
    } else {
        lua_pushboolean(L, 0);
    }
    return 1;
}
