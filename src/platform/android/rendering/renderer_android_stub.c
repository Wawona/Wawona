#include "renderer_android.h"

#ifdef __ANDROID__

int renderer_android_init(void) { return 0; }
void renderer_android_cleanup(void) {}

int renderer_android_create_pipeline(VkDevice device, VkPhysicalDevice physical_device,
                                     VkRenderPass render_pass, uint32_t queue_family,
                                     uint32_t extent_width, uint32_t extent_height) {
  (void)device;
  (void)physical_device;
  (void)render_pass;
  (void)queue_family;
  (void)extent_width;
  (void)extent_height;
  return 0;
}

void renderer_android_destroy_pipeline(void) {}

int renderer_android_cache_buffer(VkCommandBuffer cmd_buf, uint64_t buffer_id,
                                  uint32_t width, uint32_t height, uint32_t stride,
                                  uint32_t format, const uint8_t *pixels, size_t size) {
  (void)cmd_buf;
  (void)buffer_id;
  (void)width;
  (void)height;
  (void)stride;
  (void)format;
  (void)pixels;
  (void)size;
  return 0;
}

VkImageView renderer_android_get_texture(uint64_t buffer_id) {
  (void)buffer_id;
  return VK_NULL_HANDLE;
}

void renderer_android_evict_buffer(uint64_t buffer_id) { (void)buffer_id; }

void renderer_android_draw_quads(VkCommandBuffer cmd_buf, const CRenderNode *nodes,
                                 size_t node_count, uint32_t extent_width,
                                 uint32_t extent_height) {
  (void)cmd_buf;
  (void)nodes;
  (void)node_count;
  (void)extent_width;
  (void)extent_height;
}

void renderer_android_draw_cursor(VkCommandBuffer cmd_buf, uint64_t cursor_buffer_id,
                                  float cursor_x, float cursor_y, float cursor_hotspot_x,
                                  float cursor_hotspot_y, uint32_t extent_width,
                                  uint32_t extent_height) {
  (void)cmd_buf;
  (void)cursor_buffer_id;
  (void)cursor_x;
  (void)cursor_y;
  (void)cursor_hotspot_x;
  (void)cursor_hotspot_y;
  (void)extent_width;
  (void)extent_height;
}

#endif
