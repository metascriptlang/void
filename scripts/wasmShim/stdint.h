#ifndef WASM_SHIM_STDINT_H
#define WASM_SHIM_STDINT_H
typedef signed char int8_t;
typedef unsigned char uint8_t;
typedef short int16_t;
typedef unsigned short uint16_t;
typedef int int32_t;
typedef unsigned int uint32_t;
typedef long long int64_t;
typedef unsigned long long uint64_t;
typedef __UINTPTR_TYPE__ uintptr_t;
typedef __INTPTR_TYPE__ intptr_t;
#define INT32_MAX 2147483647
#define INT32_MIN (-2147483647 - 1)
#define UINT32_MAX 4294967295u
#define INT64_MAX 9223372036854775807ll
#define UINT64_MAX 18446744073709551615ull
#define SIZE_MAX __SIZE_MAX__
#endif
