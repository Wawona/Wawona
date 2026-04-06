      #include "egl_buffer_handler.h"
      #include <stdbool.h>
      #include <stdio.h>
      #include <stdlib.h>
      #include <string.h>

      // Android stub: EGL Wayland extensions are not available on Android
      // This provides stub implementations to avoid compilation errors

      static void egl_buffer_handler_translation_unit_silence(void) {}

      int egl_buffer_handler_init(struct egl_buffer_handler *handler, struct wl_display *display) {
          (void)handler; (void)display;
          // EGL Wayland extensions not available on Android
          return -1;
      }

      void egl_buffer_handler_cleanup(struct egl_buffer_handler *handler) {
          (void)handler;
      }

      int egl_buffer_handler_query_buffer(struct egl_buffer_handler *handler,
                                           struct wl_resource *buffer_resource,
                                           int32_t *width, int32_t *height,
                                           int *texture_format) {
          (void)handler; (void)buffer_resource; (void)width; (void)height; (void)texture_format;
          return -1;
      }

      void* egl_buffer_handler_create_image(struct egl_buffer_handler *handler,
                                            struct wl_resource *buffer_resource) {
          (void)handler; (void)buffer_resource;
          return NULL;
      }

      bool egl_buffer_handler_is_egl_buffer(struct egl_buffer_handler *handler,
                                             struct wl_resource *buffer_resource) {
          (void)handler; (void)buffer_resource;
          return false;
      }
