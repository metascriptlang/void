#ifndef WASM_SHIM_STDIO_H
#define WASM_SHIM_STDIO_H
#include <stddef.h>
typedef struct FILE FILE;
extern FILE *stderr;
FILE *fopen(const char *, const char *);
int fclose(FILE *);
size_t fread(void *, size_t, size_t, FILE *);
int fseek(FILE *, long, int);
long ftell(FILE *);
int fprintf(FILE *, const char *, ...);
int snprintf(char *, size_t, const char *, ...);
int vsnprintf(char *, size_t, const char *, __builtin_va_list);
#define SEEK_SET 0
#define SEEK_END 2
#endif
