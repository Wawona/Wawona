#ifndef ESUTIL_H
#define ESUTIL_H

#include <EGL/egl.h>
#include <GLES2/gl2.h>

#define ESUTIL_API

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    GLfloat m[4][4];
} ESMatrix;

void esMatrixLoadIdentity(ESMatrix *result);
void esMatrixMultiply(ESMatrix *result, ESMatrix *srcA, ESMatrix *srcB);
void esTranslate(ESMatrix *result, GLfloat tx, GLfloat ty, GLfloat tz);
void esRotate(ESMatrix *result, GLfloat angle, GLfloat x, GLfloat y, GLfloat z);
void esFrustum(ESMatrix *result, float left, float right,
               float bottom, float top, float nearZ, float farZ);

#ifdef __cplusplus
}
#endif

#endif /* ESUTIL_H */
