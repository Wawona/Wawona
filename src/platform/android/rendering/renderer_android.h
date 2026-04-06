#pragma once

/**
 * Android Renderer Interface
 *
 * On Android, Vulkan rendering is handled directly by the JNI bridge
 * (android_jni.c) which manages the swapchain, render pass, and frame
 * presentation. This header provides shared declarations used by the
 * Android rendering pipeline.
 */

#ifdef __ANDROID__

#include <stddef.h>
#include <stdint.h>
#include <vulkan/vulkan.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Render node - must match CRenderNode in android_jni.c / FFI */
typedef struct CRenderNode {
  uint64_t node_id;
  uint64_t window_id;
  uint32_t surface_id;
  uint64_t buffer_id;
  float x, y, width, height;
  float scale, opacity, corner_radius;
  int is_opaque;
  uint32_t buffer_width, buffer_height, buffer_stride, buffer_format;
  uint32_t iosurface_id;
  float anchor_output_x;
  float anchor_output_y;
  float content_rect_x;
  float content_rect_y;
  float content_rect_w;
  float content_rect_h;
} CRenderNode;

/* Vulkan resources managed by the JNI bridge */
extern VkInstance g_instance;
extern VkPhysicalDevice g_physicalDevice;
extern VkSurfaceKHR g_surface;
extern VkDevice g_device;
extern VkQueue g_queue;
extern VkSwapchainKHR g_swapchain;
extern uint32_t g_queue_family;

/* Lifecycle */
int renderer_android_init(void);
void renderer_android_cleanup(void);

/* Pipeline - caller provides device, render pass from swapchain setup */
int renderer_android_create_pipeline(
    VkDevice device, VkPhysicalDevice physical_device, VkRenderPass render_pass,
    uint32_t queue_family, uint32_t extent_width, uint32_t extent_height);
void renderer_android_destroy_pipeline(void);

/* Buffer cache - SHM upload. cmd_buf must be in recording state. */
int renderer_android_cache_buffer(VkCommandBuffer cmd_buf, uint64_t buffer_id,
                                  uint32_t width, uint32_t height,
                                  uint32_t stride, uint32_t format,
                                  const uint8_t *pixels, size_t size);
VkImageView renderer_android_get_texture(uint64_t buffer_id);
void renderer_android_evict_buffer(uint64_t buffer_id);

/* Draw scene nodes as textured quads */
void renderer_android_draw_quads(VkCommandBuffer cmd_buf,
                                 const CRenderNode *nodes, size_t node_count,
                                 uint32_t extent_width, uint32_t extent_height);

/* Draw cursor as textured quad (after scene nodes). Uses same pipeline. */
void renderer_android_draw_cursor(VkCommandBuffer cmd_buf,
                                  uint64_t cursor_buffer_id, float cursor_x,
                                  float cursor_y, float cursor_hotspot_x,
                                  float cursor_hotspot_y, uint32_t extent_width,
                                  uint32_t extent_height);

#ifdef __cplusplus
}
#endif

#endif /* __ANDROID__ */
