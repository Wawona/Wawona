/*
 * Copyright (c) 2012 Arvin Schnell <arvin.schnell@gmail.com>
 * Copyright (c) 2012 Rob Clark <rob@ti.com>
 * Copyright (c) 2013 Anand Balagopalakrishnan <anandb@ti.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sub license,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice (including the
 * next paragraph) shall be included in all copies or substantial portions
 * of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

/* Based on a egl cube test app originally written by Arvin Schnell */

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>

#include <xf86drm.h>
#include <xf86drmMode.h>
#include <drm_fourcc.h>
#include <gbm.h>

#include "esUtil.h"

#define ARRAY_SIZE(arr) (sizeof(arr) / sizeof((arr)[0]))

#define MAX_DISPLAYS 	(4)
uint8_t DISP_ID = 0;
uint8_t all_display = 0;
int8_t connector_id = -1;
char* device = "/dev/dri/card0";

static struct {
	EGLDisplay display;
	EGLConfig config;
	EGLContext context;
	EGLSurface surface;
	GLuint program;
	GLint modelviewmatrix, modelviewprojectionmatrix, normalmatrix;
	GLuint vbo;
	GLuint positionsoffset, colorsoffset, normalsoffset;
	GLuint vertex_shader, fragment_shader;
} gl;

static struct {
	struct gbm_device *dev;
	struct gbm_surface *surface;
} gbm;

static struct {
	int fd;
	uint32_t ndisp;
	uint32_t crtc_id[MAX_DISPLAYS];
	uint32_t connector_id[MAX_DISPLAYS];
	drmModeRes *resources;
	drmModeEncoder *encoder[MAX_DISPLAYS];
	uint32_t format[MAX_DISPLAYS];
	drmModeModeInfo *mode[MAX_DISPLAYS];
	drmModeConnector *connectors[MAX_DISPLAYS];
} drm;

struct drm_fb {
	struct gbm_bo *bo;
	uint32_t fb_id;
};

static uint32_t drm_fmt_to_gbm_fmt(uint32_t fmt)
{
	switch (fmt) {
		case DRM_FORMAT_XRGB8888:
			printf("DRM Format is %s\n", "DRM_FORMAT_XRGB8888");
			return GBM_FORMAT_XRGB8888;
		case DRM_FORMAT_ARGB8888:
			printf("DRM Format is %s\n", "DRM_FORMAT_ARGB8888");
			return GBM_FORMAT_ARGB8888;
		case DRM_FORMAT_RGB565:
			printf("DRM Format is %s\n", "DRM_FORMAT_RGB565");
			return GBM_FORMAT_RGB565;
		default:
			printf("Unsupported DRM format: 0x%x", fmt);
			return GBM_FORMAT_XRGB8888;
	}
}

static bool search_plane_format(uint32_t desired_format, int formats_count, uint32_t* formats)
{
	int i;

	for ( i = 0; i < formats_count; i++)
	{
		if (desired_format == formats[i])
			return true;
	}

	return false;
}

int get_drm_prop_val(int fd, drmModeObjectPropertiesPtr props,
	                 const char *name, unsigned int *p_val) {
	drmModePropertyPtr p;
	unsigned int i, prop_id = 0; /* Property ID should always be > 0 */

	for (i = 0; !prop_id && i < props->count_props; i++) {
		p = drmModeGetProperty(fd, props->props[i]);
		if (!strcmp(p->name, name)){
			prop_id = p->prop_id;
			break;
		}
		drmModeFreeProperty(p);
	}

	if (!prop_id) {
		printf("Could not find %s property\n", name);
		return(-1);
	}

	drmModeFreeProperty(p);
	*p_val = props->prop_values[i];
	return 0;
}

static bool set_drm_format(void)
{
	/* desired DRM format in order */
	static const uint32_t drm_formats[] = {DRM_FORMAT_XRGB8888, DRM_FORMAT_ARGB8888, DRM_FORMAT_RGB565};
	drmModePlaneRes *plane_res;
	bool found = false;
	int i,k;

	drmSetClientCap(drm.fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1);

	plane_res  = drmModeGetPlaneResources(drm.fd);

	if (!plane_res) {
		printf("drmModeGetPlaneResources failed: %s\n", strerror(errno));
		drmSetClientCap(drm.fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 0);
		return false;
	}

	/*
	 * find the plane connected to crtc_id (the primary plane) and then find the desired pixel format
	 * from the plane format list
	 */
	for (i = 0; i < plane_res->count_planes; i++)
	{
		drmModePlane *plane = drmModeGetPlane(drm.fd, plane_res->planes[i]);
		drmModeObjectProperties *props;
		unsigned int plane_type;

		if(plane == NULL)
			continue;

		props = drmModeObjectGetProperties(drm.fd, plane->plane_id, DRM_MODE_OBJECT_PLANE);

		if(props == NULL){
			printf("plane (%d) properties not found\n",  plane->plane_id);
			drmModeFreePlane(plane);
			continue;
		}

		if(get_drm_prop_val(drm.fd, props, "type",  &plane_type) < 0)
		{
			printf("plane (%d) type value not found\n",  plane->plane_id);
			drmModeFreeObjectProperties(props);
			drmModeFreePlane(plane);
			continue;
		}

		if (plane_type != DRM_PLANE_TYPE_PRIMARY)
		{
			drmModeFreeObjectProperties(props);
			drmModeFreePlane(plane);
			continue;
		}
		else if (!plane->crtc_id)
		{
			plane->crtc_id = drm.crtc_id[drm.ndisp];
		}

		drmModeFreeObjectProperties(props);

		if (plane->crtc_id == drm.crtc_id[drm.ndisp])
		{
			for (k = 0; k < ARRAY_SIZE(drm_formats); k++)
			{
				if (search_plane_format(drm_formats[k], plane->count_formats, plane->formats))
				{
					drm.format[drm.ndisp] = drm_formats[k];
					drmModeFreePlane(plane);
					drmModeFreePlaneResources(plane_res);
					drmSetClientCap(drm.fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 0);
					return true;
				}
			}
		}

		drmModeFreePlane(plane);
	}

	drmModeFreePlaneResources(plane_res);
	drmSetClientCap(drm.fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 0);
	return false;
}

static int init_drm(void)
{
	drmModeRes *resources;
	drmModeConnector *connector = NULL;
	drmModeEncoder *encoder = NULL;
	drmModeCrtc *crtc = NULL;

	int i, j, k;
	uint32_t maxRes, curRes;

	/* Open default dri device */
	drm.fd = open(device, O_RDWR | O_CLOEXEC);
	if (drm.fd < 0) {
		printf("could not open drm device %s\n", device);
		return -1;
	}

	resources = drmModeGetResources(drm.fd);
	if (!resources) {
		printf("drmModeGetResources failed: %s\n", strerror(errno));
		return -1;
	}
	drm.resources = resources;

	/* find a connected connector: */
	for (i = 0; i < resources->count_connectors; i++) {
		connector = drmModeGetConnector(drm.fd, resources->connectors[i]);
		if (connector->connection == DRM_MODE_CONNECTED) {

			/* find the matched encoders */
			for (j=0; j<connector->count_encoders; j++) {
				encoder = drmModeGetEncoder(drm.fd, connector->encoders[j]);

				/* Take the fisrt one, if none is assigned */
				if (!connector->encoder_id)
				{
					connector->encoder_id = encoder->encoder_id;
				}

				if (encoder->encoder_id == connector->encoder_id)
				{
					/* find the first valid CRTC if not assigned */
					if (!encoder->crtc_id)
					{
						for (k = 0; k < resources->count_crtcs; ++k) {
							/* check whether this CRTC works with the encoder */
							if (!(encoder->possible_crtcs & (1 << k)))
								continue;

							encoder->crtc_id = resources->crtcs[k];
							break;
						}

						if (!encoder->crtc_id)
						{
							printf("Encoder(%d): no CRTC find!\n", encoder->encoder_id);
							drmModeFreeEncoder(encoder);
							encoder = NULL;
							continue;
						}
					}

					break;
				}

				drmModeFreeEncoder(encoder);
				encoder = NULL;
			}

			if (!encoder) {
				printf("Connector (%d): no encoder!\n", connector->connector_id);
				drmModeFreeConnector(connector);
				continue;
			}

			/* choose the current or first supported mode */
			crtc = drmModeGetCrtc(drm.fd, encoder->crtc_id);
			for (j = 0; j < connector->count_modes; j++)
			{
				if (crtc->mode_valid)
				{
					if ((connector->modes[j].hdisplay == crtc->width) &&
					(connector->modes[j].vdisplay == crtc->height))
					{
						drm.mode[drm.ndisp] = &connector->modes[j];
						break;
					}
				}
				else
				{
					if ((connector->modes[j].hdisplay == crtc->x) &&
					   (connector->modes[j].vdisplay == crtc->y))
					{
						drm.mode[drm.ndisp] = &connector->modes[j];
						break;
					}
				}
			}

			if(j >= connector->count_modes)
				drm.mode[drm.ndisp] = &connector->modes[0];

			drm.connector_id[drm.ndisp] = connector->connector_id;

			drm.encoder[drm.ndisp] = encoder;
			drm.crtc_id[drm.ndisp] = encoder->crtc_id;
			drm.connectors[drm.ndisp] = connector;

			if (!set_drm_format())
			{
				// Error handling
				printf("No desired pixel format found!\n");
				return -1;
			}

			printf("### Display [%d]: CRTC = %d, Connector = %d, format = 0x%x\n", drm.ndisp, drm.crtc_id[drm.ndisp], drm.connector_id[drm.ndisp], drm.format[drm.ndisp]);
			printf("\tMode chosen [%s] : Clock => %d, Vertical refresh => %d, Type => %d\n", drm.mode[drm.ndisp]->name, drm.mode[drm.ndisp]->clock, drm.mode[drm.ndisp]->vrefresh, drm.mode[drm.ndisp]->type);
			printf("\tHorizontal => %d, %d, %d, %d, %d\n", drm.mode[drm.ndisp]->hdisplay, drm.mode[drm.ndisp]->hsync_start, drm.mode[drm.ndisp]->hsync_end, drm.mode[drm.ndisp]->htotal, drm.mode[drm.ndisp]->hskew);
			printf("\tVertical => %d, %d, %d, %d, %d\n", drm.mode[drm.ndisp]->vdisplay, drm.mode[drm.ndisp]->vsync_start, drm.mode[drm.ndisp]->vsync_end, drm.mode[drm.ndisp]->vtotal, drm.mode[drm.ndisp]->vscan);

			/* If a connector_id is specified, use the corresponding display */
			if ((connector_id != -1) && (connector_id == drm.connector_id[drm.ndisp]))
				DISP_ID = drm.ndisp;

			/* If all displays are enabled, choose the connector with maximum
			* resolution as the primary display */
			if (all_display) {
				maxRes = drm.mode[DISP_ID]->vdisplay * drm.mode[DISP_ID]->hdisplay;
				curRes = drm.mode[drm.ndisp]->vdisplay * drm.mode[drm.ndisp]->hdisplay;

				if (curRes > maxRes)
					DISP_ID = drm.ndisp;
			}

			drm.ndisp++;
		} else {
			drmModeFreeConnector(connector);
		}
	}

	if (drm.ndisp == 0) {
		/* we could be fancy and listen for hotplug events and wait for
		 * a connector..
		 */
		printf("no connected connector!\n");
		return -1;
	}

	return 0;
}

static int init_gbm(void)
{
	printf("gbm.dev = %p, gbm.surface = %p\n", gbm.dev, gbm.surface);
	
	gbm.dev = gbm_create_device(drm.fd);

	gbm.surface = gbm_surface_create(gbm.dev,
			drm.mode[DISP_ID]->hdisplay, drm.mode[DISP_ID]->vdisplay,
			drm_fmt_to_gbm_fmt(drm.format[DISP_ID]),
			GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING);
	if (!gbm.surface) {
		printf("failed to create gbm surface\n");
		return -1;
	}

	printf("gbm.dev = %p, gbm.surface = %p\n", gbm.dev, gbm.surface);
	return 0;
}

static int init_gl(void)
{
	EGLint major, minor, n;
	GLint ret;

	static const GLfloat vVertices[] = {
			// front
			-1.0f, -1.0f, +1.0f, // point blue
			+1.0f, -1.0f, +1.0f, // point magenta
			-1.0f, +1.0f, +1.0f, // point cyan
			+1.0f, +1.0f, +1.0f, // point white
			// back
			+1.0f, -1.0f, -1.0f, // point red
			-1.0f, -1.0f, -1.0f, // point black
			+1.0f, +1.0f, -1.0f, // point yellow
			-1.0f, +1.0f, -1.0f, // point green
			// right
			+1.0f, -1.0f, +1.0f, // point magenta
			+1.0f, -1.0f, -1.0f, // point red
			+1.0f, +1.0f, +1.0f, // point white
			+1.0f, +1.0f, -1.0f, // point yellow
			// left
			-1.0f, -1.0f, -1.0f, // point black
			-1.0f, -1.0f, +1.0f, // point blue
			-1.0f, +1.0f, -1.0f, // point green
			-1.0f, +1.0f, +1.0f, // point cyan
			// top
			-1.0f, +1.0f, +1.0f, // point cyan
			+1.0f, +1.0f, +1.0f, // point white
			-1.0f, +1.0f, -1.0f, // point green
			+1.0f, +1.0f, -1.0f, // point yellow
			// bottom
			-1.0f, -1.0f, -1.0f, // point black
			+1.0f, -1.0f, -1.0f, // point red
			-1.0f, -1.0f, +1.0f, // point blue
			+1.0f, -1.0f, +1.0f  // point magenta
	};

	static const GLfloat vColors[] = {
			// front
			0.0f,  0.0f,  1.0f, // blue
			1.0f,  0.0f,  1.0f, // magenta
			0.0f,  1.0f,  1.0f, // cyan
			1.0f,  1.0f,  1.0f, // white
			// back
			1.0f,  0.0f,  0.0f, // red
			0.0f,  0.0f,  0.0f, // black
			1.0f,  1.0f,  0.0f, // yellow
			0.0f,  1.0f,  0.0f, // green
			// right
			1.0f,  0.0f,  1.0f, // magenta
			1.0f,  0.0f,  0.0f, // red
			1.0f,  1.0f,  1.0f, // white
			1.0f,  1.0f,  0.0f, // yellow
			// left
			0.0f,  0.0f,  0.0f, // black
			0.0f,  0.0f,  1.0f, // blue
			0.0f,  1.0f,  0.0f, // green
			0.0f,  1.0f,  1.0f, // cyan
			// top
			0.0f,  1.0f,  1.0f, // cyan
			1.0f,  1.0f,  1.0f, // white
			0.0f,  1.0f,  0.0f, // green
			1.0f,  1.0f,  0.0f, // yellow
			// bottom
			0.0f,  0.0f,  0.0f, // black
			1.0f,  0.0f,  0.0f, // red
			0.0f,  0.0f,  1.0f, // blue
			1.0f,  0.0f,  1.0f  // magenta
	};

	static const GLfloat vNormals[] = {
			// front
			+0.0f, +0.0f, +1.0f, // forward
			+0.0f, +0.0f, +1.0f, // forward
			+0.0f, +0.0f, +1.0f, // forward
			+0.0f, +0.0f, +1.0f, // forward
			// back
			+0.0f, +0.0f, -1.0f, // backbard
			+0.0f, +0.0f, -1.0f, // backbard
			+0.0f, +0.0f, -1.0f, // backbard
			+0.0f, +0.0f, -1.0f, // backbard
			// right
			+1.0f, +0.0f, +0.0f, // right
			+1.0f, +0.0f, +0.0f, // right
			+1.0f, +0.0f, +0.0f, // right
			+1.0f, +0.0f, +0.0f, // right
			// left
			-1.0f, +0.0f, +0.0f, // left
			-1.0f, +0.0f, +0.0f, // left
			-1.0f, +0.0f, +0.0f, // left
			-1.0f, +0.0f, +0.0f, // left
			// top
			+0.0f, +1.0f, +0.0f, // up
			+0.0f, +1.0f, +0.0f, // up
			+0.0f, +1.0f, +0.0f, // up
			+0.0f, +1.0f, +0.0f, // up
			// bottom
			+0.0f, -1.0f, +0.0f, // down
			+0.0f, -1.0f, +0.0f, // down
			+0.0f, -1.0f, +0.0f, // down
			+0.0f, -1.0f, +0.0f  // down
	};

	static const EGLint context_attribs[] = {
		EGL_CONTEXT_CLIENT_VERSION, 2,
		EGL_NONE
	};

	static const EGLint config_attribs[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
		EGL_RED_SIZE, 1,
		EGL_GREEN_SIZE, 1,
		EGL_BLUE_SIZE, 1,
		EGL_ALPHA_SIZE, 0,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
		EGL_NONE
	};

	static const char *vertex_shader_source =
			"uniform mat4 modelviewMatrix;      \n"
			"uniform mat4 modelviewprojectionMatrix;\n"
			"uniform mat3 normalMatrix;         \n"
			"                                   \n"
			"attribute vec4 in_position;        \n"
			"attribute vec3 in_normal;          \n"
			"attribute vec4 in_color;           \n"
			"\n"
			"vec4 lightSource = vec4(2.0, 2.0, 20.0, 0.0);\n"
			"                                   \n"
			"varying vec4 vVaryingColor;        \n"
			"                                   \n"
			"void main()                        \n"
			"{                                  \n"
			"    gl_Position = modelviewprojectionMatrix * in_position;\n"
			"    vec3 vEyeNormal = normalMatrix * in_normal;\n"
			"    vec4 vPosition4 = modelviewMatrix * in_position;\n"
			"    vec3 vPosition3 = vPosition4.xyz / vPosition4.w;\n"
			"    vec3 vLightDir = normalize(lightSource.xyz - vPosition3);\n"
			"    float diff = max(0.0, dot(vEyeNormal, vLightDir));\n"
			"    vVaryingColor = vec4(diff * in_color.rgb, 1.0);\n"
			"}                                  \n";

	static const char *fragment_shader_source =
			"precision mediump float;           \n"
			"                                   \n"
			"varying vec4 vVaryingColor;        \n"
			"                                   \n"
			"void main()                        \n"
			"{                                  \n"
			"    gl_FragColor = vVaryingColor;  \n"
			"}                                  \n";

	gl.display = eglGetDisplay(gbm.dev);
	printf("gl.display = %p\n", gl.display);

	if (!eglInitialize(gl.display, &major, &minor)) {
		printf("failed to initialize\n");
		return -1;
	}

	printf("Using display %p with EGL version %d.%d\n",
			gl.display, major, minor);

	printf("EGL Version \"%s\"\n", eglQueryString(gl.display, EGL_VERSION));
	printf("EGL Vendor \"%s\"\n", eglQueryString(gl.display, EGL_VENDOR));
	printf("EGL Extensions \"%s\"\n", eglQueryString(gl.display, EGL_EXTENSIONS));

	if (!eglBindAPI(EGL_OPENGL_ES_API)) {
		printf("failed to bind api EGL_OPENGL_ES_API\n");
		return -1;
	}

	if (!eglChooseConfig(gl.display, config_attribs, &gl.config, 1, &n) || n != 1) {
		printf("failed to choose config: %d\n", n);
		return -1;
	}

	gl.context = eglCreateContext(gl.display, gl.config,
			EGL_NO_CONTEXT, context_attribs);
	if (gl.context == NULL) {
		printf("failed to create context\n");
		return -1;
	}

	gl.surface = eglCreateWindowSurface(gl.display, gl.config, gbm.surface, NULL);
	if (gl.surface == EGL_NO_SURFACE) {
		printf("failed to create egl surface\n");
		return -1;
	}

	/* connect the context to the surface */
	eglMakeCurrent(gl.display, gl.surface, gl.surface, gl.context);


	gl.vertex_shader = glCreateShader(GL_VERTEX_SHADER);

	glShaderSource(gl.vertex_shader, 1, &vertex_shader_source, NULL);
	glCompileShader(gl.vertex_shader);

	glGetShaderiv(gl.vertex_shader, GL_COMPILE_STATUS, &ret);
	if (!ret) {
		char *log;

		printf("vertex shader compilation failed!:\n");
		glGetShaderiv(gl.vertex_shader, GL_INFO_LOG_LENGTH, &ret);
		if (ret > 1) {
			log = malloc(ret);
			glGetShaderInfoLog(gl.vertex_shader, ret, NULL, log);
			printf("%s", log);
		}

		return -1;
	}

	gl.fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);

	glShaderSource(gl.fragment_shader, 1, &fragment_shader_source, NULL);
	glCompileShader(gl.fragment_shader);

	glGetShaderiv(gl.fragment_shader, GL_COMPILE_STATUS, &ret);
	if (!ret) {
		char *log;

		printf("fragment shader compilation failed!:\n");
		glGetShaderiv(gl.fragment_shader, GL_INFO_LOG_LENGTH, &ret);

		if (ret > 1) {
			log = malloc(ret);
			glGetShaderInfoLog(gl.fragment_shader, ret, NULL, log);
			printf("%s", log);
		}

		return -1;
	}

	gl.program = glCreateProgram();

	glAttachShader(gl.program, gl.vertex_shader);
	glAttachShader(gl.program, gl.fragment_shader);

	glBindAttribLocation(gl.program, 0, "in_position");
	glBindAttribLocation(gl.program, 1, "in_normal");
	glBindAttribLocation(gl.program, 2, "in_color");

	glLinkProgram(gl.program);

	glGetProgramiv(gl.program, GL_LINK_STATUS, &ret);
	if (!ret) {
		char *log;

		printf("program linking failed!:\n");
		glGetProgramiv(gl.program, GL_INFO_LOG_LENGTH, &ret);

		if (ret > 1) {
			log = malloc(ret);
			glGetProgramInfoLog(gl.program, ret, NULL, log);
			printf("%s", log);
		}

		return -1;
	}

	glUseProgram(gl.program);

	gl.modelviewmatrix = glGetUniformLocation(gl.program, "modelviewMatrix");
	gl.modelviewprojectionmatrix = glGetUniformLocation(gl.program, "modelviewprojectionMatrix");
	gl.normalmatrix = glGetUniformLocation(gl.program, "normalMatrix");

	glViewport(0, 0, drm.mode[DISP_ID]->hdisplay, drm.mode[DISP_ID]->vdisplay);
	glEnable(GL_CULL_FACE);

	gl.positionsoffset = 0;
	gl.colorsoffset = sizeof(vVertices);
	gl.normalsoffset = sizeof(vVertices) + sizeof(vColors);
	glGenBuffers(1, &gl.vbo);
	glBindBuffer(GL_ARRAY_BUFFER, gl.vbo);
	glBufferData(GL_ARRAY_BUFFER, sizeof(vVertices) + sizeof(vColors) + sizeof(vNormals), 0, GL_STATIC_DRAW);
	glBufferSubData(GL_ARRAY_BUFFER, gl.positionsoffset, sizeof(vVertices), &vVertices[0]);
	glBufferSubData(GL_ARRAY_BUFFER, gl.colorsoffset, sizeof(vColors), &vColors[0]);
	glBufferSubData(GL_ARRAY_BUFFER, gl.normalsoffset, sizeof(vNormals), &vNormals[0]);
	glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)gl.positionsoffset);
	glEnableVertexAttribArray(0);
	glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)gl.normalsoffset);
	glEnableVertexAttribArray(1);
	glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)gl.colorsoffset);
	glEnableVertexAttribArray(2);

	return 0;
}

static void exit_gbm(void)
{
        gbm_surface_destroy(gbm.surface);
        gbm_device_destroy(gbm.dev);
        return;
}

static void exit_gl(void)
{
        glDeleteProgram(gl.program);
        glDeleteBuffers(1, &gl.vbo);
        glDeleteShader(gl.fragment_shader);
        glDeleteShader(gl.vertex_shader);
        eglDestroySurface(gl.display, gl.surface);
        eglDestroyContext(gl.display, gl.context);
        eglTerminate(gl.display);
        return;
}

static void exit_drm(void)
{
        int i;

        for (i = 0; i < drm.resources->count_connectors; i++) {
                drmModeFreeEncoder(drm.encoder[i]);
                drmModeFreeConnector(drm.connectors[i]);
        }
        drmModeFreeResources(drm.resources);
        close(drm.fd);
        return;
}

void cleanup_kmscube(void)
{
	exit_gl();
	exit_gbm();
	exit_drm();
	printf("Cleanup of GL, GBM and DRM completed\n");
	return;
}

static void draw(uint32_t i)
{
	ESMatrix modelview;

	/* clear the color buffer */
	glClearColor(0.5, 0.5, 0.5, 1.0);
	glClear(GL_COLOR_BUFFER_BIT);

	esMatrixLoadIdentity(&modelview);
	esTranslate(&modelview, 0.0f, 0.0f, -8.0f);
	esRotate(&modelview, 45.0f + (0.25f * i), 1.0f, 0.0f, 0.0f);
	esRotate(&modelview, 45.0f - (0.5f * i), 0.0f, 1.0f, 0.0f);
	esRotate(&modelview, 10.0f + (0.15f * i), 0.0f, 0.0f, 1.0f);

	GLfloat aspect = (GLfloat)(drm.mode[DISP_ID]->vdisplay) / (GLfloat)(drm.mode[DISP_ID]->hdisplay);

	ESMatrix projection;
	esMatrixLoadIdentity(&projection);
	esFrustum(&projection, -2.8f, +2.8f, -2.8f * aspect, +2.8f * aspect, 6.0f, 10.0f);

	ESMatrix modelviewprojection;
	esMatrixLoadIdentity(&modelviewprojection);
	esMatrixMultiply(&modelviewprojection, &modelview, &projection);

	float normal[9];
	normal[0] = modelview.m[0][0];
	normal[1] = modelview.m[0][1];
	normal[2] = modelview.m[0][2];
	normal[3] = modelview.m[1][0];
	normal[4] = modelview.m[1][1];
	normal[5] = modelview.m[1][2];
	normal[6] = modelview.m[2][0];
	normal[7] = modelview.m[2][1];
	normal[8] = modelview.m[2][2];

	glUniformMatrix4fv(gl.modelviewmatrix, 1, GL_FALSE, &modelview.m[0][0]);
	glUniformMatrix4fv(gl.modelviewprojectionmatrix, 1, GL_FALSE, &modelviewprojection.m[0][0]);
	glUniformMatrix3fv(gl.normalmatrix, 1, GL_FALSE, normal);

	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	glDrawArrays(GL_TRIANGLE_STRIP, 4, 4);
	glDrawArrays(GL_TRIANGLE_STRIP, 8, 4);
	glDrawArrays(GL_TRIANGLE_STRIP, 12, 4);
	glDrawArrays(GL_TRIANGLE_STRIP, 16, 4);
	glDrawArrays(GL_TRIANGLE_STRIP, 20, 4);
}

static void
drm_fb_destroy_callback(struct gbm_bo *bo, void *data)
{
	struct drm_fb *fb = data;
	struct gbm_device *gbm = gbm_bo_get_device(bo);

	if (fb->fb_id)
		drmModeRmFB(drm.fd, fb->fb_id);

	free(fb);
}

static struct drm_fb * drm_fb_get_from_bo(struct gbm_bo *bo)
{
	struct drm_fb *fb = gbm_bo_get_user_data(bo);
	uint32_t width, height, format;
	uint32_t bo_handles[4] = {0}, offsets[4] = {0}, pitches[4] = {0};
	int ret;

	if (fb)
		return fb;

	fb = calloc(1, sizeof *fb);
	fb->bo = bo;

	width = gbm_bo_get_width(bo);
	height = gbm_bo_get_height(bo);
	pitches[0] = gbm_bo_get_stride(bo);
	bo_handles[0] = gbm_bo_get_handle(bo).u32;
	format = gbm_bo_get_format(bo);

	ret = drmModeAddFB2(drm.fd, width, height, format, bo_handles, pitches, offsets, &fb->fb_id, 0);
	if (ret) {
		printf("failed to create fb: %s\n", strerror(errno));
		free(fb);
		return NULL;
	}

	gbm_bo_set_user_data(bo, fb, drm_fb_destroy_callback);

	return fb;
}

static void page_flip_handler(int fd, unsigned int frame,
		  unsigned int sec, unsigned int usec, void *data)
{
	int *waiting_for_flip = data;
	*waiting_for_flip = *waiting_for_flip - 1;
}

void print_usage()
{
	printf("Usage : kmscube <options>\n");
	printf("\t-h : Help\n");
	printf("\t-a : Enable all displays\n");
	printf("\t-c <id> : Display using connector_id [if not specified, use the first connected connector]\n");
	printf("\t-d /dev/dri/cardX : DRM device to be used. [If not specified, use /dev/dri/card0]\n");
	printf("\t-n <number> (optional): Number of frames to render\n");
}

void kms_signalhandler(int signum)
{
	switch(signum) {
	case SIGINT:
        case SIGTERM:
                /* Allow the pending page flip requests to be completed before
                 * the teardown sequence */
                sleep(1);
                printf("Handling signal number = %d\n", signum);
		cleanup_kmscube();
		break;
	default:
		printf("Unknown signal\n");
		break;
	}
	exit(1);
}

int main(int argc, char *argv[])
{
	fd_set fds;
	drmEventContext evctx = {
			.version = DRM_EVENT_CONTEXT_VERSION,
			.page_flip_handler = page_flip_handler,
	};
	struct gbm_bo *bo;
	struct drm_fb *fb;
	uint32_t i = 0;
	int ret;
	int opt;
	int frame_count = -1;

	signal(SIGINT, kms_signalhandler);
	signal(SIGTERM, kms_signalhandler);

	while ((opt = getopt(argc, argv, "ahcd:n:")) != -1) {
		switch(opt) {
		case 'a':
			all_display = 1;
			break;

		case 'h':
			print_usage();
			return 0;

		case 'c':
			connector_id = atoi(optarg);
			break;
		case 'd':
			device = optarg;
			break;
		case 'n':
			frame_count = atoi(optarg);
			break;


		default:
			printf("Undefined option %s\n", argv[optind]);
			print_usage();
			return -1;
		}
	}

	if (all_display) {
		printf("### Enabling all displays\n");
		connector_id = -1;
	}

	ret = init_drm();
	if (ret) {
		printf("failed to initialize DRM\n");
		return ret;
	}
	printf("### Primary display => ConnectorId = %d, Resolution = %dx%d\n",
			drm.connector_id[DISP_ID], drm.mode[DISP_ID]->hdisplay,
			drm.mode[DISP_ID]->vdisplay);

	FD_ZERO(&fds);
	FD_SET(drm.fd, &fds);

	ret = init_gbm();
	if (ret) {
		printf("failed to initialize GBM\n");
		return ret;
	}

	printf("init gbm success!\n");

	ret = init_gl();
	if (ret) {
		printf("failed to initialize EGL\n");
		return ret;
	}

	printf("init gl success!\n");

	/* clear the color buffer */
	glClearColor(0.5, 0.5, 0.5, 1.0);
	glClear(GL_COLOR_BUFFER_BIT);
	eglSwapBuffers(gl.display, gl.surface);
	bo = gbm_surface_lock_front_buffer(gbm.surface);
	fb = drm_fb_get_from_bo(bo);

	printf("clear color success!\n");
	/* set mode: */
	if (all_display) {
		for (i=0; i<drm.ndisp; i++) {
			ret = drmModeSetCrtc(drm.fd, drm.crtc_id[i], fb->fb_id, 0, 0,
					&drm.connector_id[i], 1, drm.mode[i]);
			if (ret) {
				printf("display %d failed to set mode: %s\n", i, strerror(errno));
				return ret;
			}
		}
	} else {
		ret = drmModeSetCrtc(drm.fd, drm.crtc_id[DISP_ID], fb->fb_id,
				0, 0, &drm.connector_id[DISP_ID], 1, drm.mode[DISP_ID]);
		if (ret) {
			printf("display %d failed to set mode: %s\n", DISP_ID, strerror(errno));
			return ret;
		}
	}

	printf("prepare enter while loop!\n");
	while (frame_count != 0) {
		struct gbm_bo *next_bo;
		int waiting_for_flip;
		int cc;

		draw(i++);

		eglSwapBuffers(gl.display, gl.surface);
		next_bo = gbm_surface_lock_front_buffer(gbm.surface);
		fb = drm_fb_get_from_bo(next_bo);

		/*
		 * Here you could also update drm plane layers if you want
		 * hw composition
		 */

		if (all_display) {
			for (cc=0;cc<drm.ndisp; cc++) {
				ret = drmModePageFlip(drm.fd, drm.crtc_id[cc], fb->fb_id,
					DRM_MODE_PAGE_FLIP_EVENT, &waiting_for_flip);
				if (ret) {
					printf("failed to queue page flip: %s\n", strerror(errno));
					return -1;
				}
			}
			waiting_for_flip = drm.ndisp;
		} else {
			ret = drmModePageFlip(drm.fd, drm.crtc_id[DISP_ID], fb->fb_id,
					DRM_MODE_PAGE_FLIP_EVENT, &waiting_for_flip);
			if (ret) {
				printf("failed to queue page flip: %s\n", strerror(errno));
				return -1;
			}
			waiting_for_flip = 1;
		}

		while (waiting_for_flip) {
			ret = select(drm.fd + 1, &fds, NULL, NULL, NULL);
			if (ret < 0) {
				printf("select err: %s\n", strerror(errno));
				return ret;
			} else if (ret == 0) {
				printf("select timeout!\n");
				return -1;
			} else if (FD_ISSET(0, &fds)) {
				continue;
			}
			drmHandleEvent(drm.fd, &evctx);
		}

		/* release last buffer to render on again: */
		gbm_surface_release_buffer(gbm.surface, bo);
		bo = next_bo;

                if(frame_count >= 0)
		        frame_count--;
	}

	cleanup_kmscube();
	printf("\n Exiting kmscube \n");

	return ret;
}
