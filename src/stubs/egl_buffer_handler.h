      #pragma once
      #include <stdbool.h>
      #include <stdint.h>
      struct egl_buffer_handler;
      struct wl_display;
      struct wl_resource;
      int egl_buffer_handler_init(struct egl_buffer_handler *handler, struct wl_display *display);
      void egl_buffer_handler_cleanup(struct egl_buffer_handler *handler);
      int egl_buffer_handler_query_buffer(struct egl_buffer_handler *handler,
                                           struct wl_resource *buffer_resource,
                                           int32_t *width, int32_t *height,
                                           int *texture_format);
      void* egl_buffer_handler_create_image(struct egl_buffer_handler *handler,
                                            struct wl_resource *buffer_resource);
      bool egl_buffer_handler_is_egl_buffer(struct egl_buffer_handler *handler,
                                             struct wl_resource *buffer_resource);
