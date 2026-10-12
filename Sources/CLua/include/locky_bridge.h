#ifndef LOCKY_BRIDGE_H
#define LOCKY_BRIDGE_H

#include <stddef.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

/*
 * The C side of Locky's Lua runtime.
 *
 * Lua reports errors with longjmp. A longjmp must never unwind through Swift frames, so every place where
 * Lua may raise an error on Locky's behalf is C: the trampoline that calls Swift functions, the hook that
 * enforces the time budget, and the protected call. Swift code reads and writes the stack only with raw
 * functions that cannot raise.
 */

/* Calls the host's function number `index`. Returns how many results it pushed, or -1 after pushing an
 * error message, which the trampoline then raises from C. */
typedef int (*LockyDispatch)(lua_State *L, void *context, int index);

/* What the count hook enforces for one Lua state. The host allocates it and keeps it alive until
 * lua_close returns. Every coroutine of the state shares it. */
typedef struct LockyGuard {
    double deadline;      /* on locky_now()'s clock; 0 means no deadline */
    int timed_out;        /* set once the deadline passes; cleared when the protected call returns */
    size_t used;          /* bytes the state holds now */
    size_t peak;
    size_t soft_limit;    /* above this, Lua code fails with a memory error at its next check */
    size_t hard_limit;    /* an allocation that would pass this fails at once */
    int over_soft;        /* set by the allocator; the hook collects garbage, then checks again */
    int memory_error;     /* set when the hook raised a memory error; cleared when the protected call returns */
    LockyDispatch dispatch;
    void *context;        /* passed to dispatch: the host's object */
} LockyGuard;

/* A state that allocates through `guard` and checks it every 1000 instructions. NULL when out of memory. */
lua_State *locky_newstate(LockyGuard *guard);

LockyGuard *locky_guard(lua_State *L);

/* The standard libraries without the parts a plugin must not have: os.exit, os.execute, io.popen,
 * package.loadlib, C modules, string.dump, and every debug function except traceback and getinfo. */
void locky_openlibs(lua_State *L);

/* Pushes a Lua function that calls the host's function number `index`. */
void locky_pushnative(lua_State *L, int index);

/* lua_pcall with a traceback, under a time budget in seconds (0: no budget of its own). A nested call
 * never extends the budget of the call around it. */
int locky_pcall(lua_State *L, int nargs, int nresults, double budget);

/* Loads Lua source (never bytecode). `chunkname` follows lua_load's rules, such as "@path". */
int locky_loadbuffer(lua_State *L, const char *source, size_t length, const char *chunkname);

/* A Lua function: false, or the reason the current protected call must end (it ran out of time, or memory).
 * The Lua prelude uses it to stop pcall, xpcall, load, and coroutines from swallowing that error. */
int locky_budget_exceeded(lua_State *L);

/* Monotonic seconds. */
double locky_now(void);

/* "Lua 5.5.1". */
static inline const char *locky_lua_release(void) { return LUA_RELEASE; }

/* Function-like macros and variadic functions Swift cannot import. */
static inline void locky_gc_collect(lua_State *L) { lua_gc(L, LUA_GCCOLLECT); }
static inline int locky_registryindex(void) { return LUA_REGISTRYINDEX; }
static inline void locky_pop(lua_State *L, int n) { lua_settop(L, -(n) - 1); }

#endif
