// A Windows `emcc.exe` (and `em++`, `emar`, `emranlib`) that msc can actually spawn.
//
// Why this exists: emscripten ships `emcc.bat`, not `emcc.exe`, and msc spawns its C
// compiler as an executable, so an `--os=emcc` build on Windows dies with
// `@compile failed for .../system.c (exit -1)` before it compiles a line. Going through
// cmd.exe instead is not a fix: msc passes flags like `-DMBEDTLS_CONFIG_FILE=<...>`, and
// cmd reads `<` and `>` as redirection.
//
// So: a real .exe that runs the emscripten python entry point directly, with argv handed
// straight to CreateProcess through _spawnv — which quotes for CreateProcess, not for cmd.
//
// Built by scripts/build-emcc-shim.sh into out/emcc-shim/, which scripts/build-web.sh puts
// first on PATH. The paths come from the environment so one binary serves any emsdk:
//   VOID_EMSDK_PYTHON  the interpreter emsdk was installed with (plain `python3` on this
//                      box is the Microsoft Store alias and will not do)
//   VOID_EMSDK_ROOT    the emsdk checkout; the scripts live in upstream/emscripten/

#include <process.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *toolName(const char *argv0) {
	const char *base = argv0;
	for (const char *p = argv0; *p; p++) {
		if (*p == '/' || *p == '\\') base = p + 1;
	}
	static char name[64];
	size_t n = 0;
	while (base[n] && n + 1 < sizeof(name)) {
		if ((base[n] == '.') && (strcmp(base + n, ".exe") == 0 || strcmp(base + n, ".EXE") == 0)) break;
		name[n] = base[n];
		n++;
	}
	name[n] = '\0';
	return name;
}

int main(int argc, char **argv) {
	const char *python = getenv("VOID_EMSDK_PYTHON");
	const char *root = getenv("VOID_EMSDK_ROOT");
	if (!python || !root) {
		fprintf(stderr, "emccShim: set VOID_EMSDK_PYTHON and VOID_EMSDK_ROOT "
			"(scripts/build-web.sh does)\n");
		return 1;
	}

	static char script[1024];
	snprintf(script, sizeof(script), "%s/upstream/emscripten/%s.py", root, toolName(argv[0]));

	const char **args = (const char **)calloc((size_t)argc + 3u, sizeof(char *));
	if (!args) return 1;
	int n = 0;
	args[n++] = python;
	args[n++] = "-E";          // ignore PYTHON* in the environment; emsdk sets its own
	args[n++] = script;
	for (int i = 1; i < argc; i++) args[n++] = argv[i];
	args[n] = NULL;

	intptr_t status = _spawnv(_P_WAIT, python, args);
	free(args);
	if (status < 0) {
		fprintf(stderr, "emccShim: could not run %s %s\n", python, script);
		return 1;
	}
	return (int)status;
}
