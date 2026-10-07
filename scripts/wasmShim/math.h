#ifndef WASM_SHIM_MATH_H
#define WASM_SHIM_MATH_H
double floor(double); double ceil(double); double fabs(double); double sqrt(double); double pow(double, double);
double fmod(double, double); double acos(double); double cos(double); double sin(double); double tan(double); double atan2(double, double);
float floorf(float); float ceilf(float); float fabsf(float); float sqrtf(float); float powf(float, float); float fmodf(float, float);
float sinf(float); float cosf(float); float tanf(float); float atan2f(float, float); float roundf(float); float truncf(float);
#define INFINITY (__builtin_inff())
#define NAN (__builtin_nanf(""))
int isnan(double); int isinf(double);
#endif
