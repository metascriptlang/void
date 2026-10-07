#ifndef WASM_SHIM_STDLIB_H
#define WASM_SHIM_STDLIB_H
#include <stddef.h>
void *malloc(size_t);
void *calloc(size_t, size_t);
void *realloc(void *, size_t);
void free(void *);
void abort(void);
void qsort(void *, size_t, size_t, int (*)(const void *, const void *));
#endif
