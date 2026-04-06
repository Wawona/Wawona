/**
 * Android Renderer - Vulkan textured quad pipeline
 *
 * Provides buffer cache (SHM -> VkImage upload), textured quad rendering,
 * and cursor drawing. The primary Vulkan lifecycle (instance, device,
 * swapchain) is managed in android_jni.c.
 */

#ifdef __ANDROID__

#include "renderer_android.h"
#include "shader_spv.h"
#include <android/log.h>
#include <stdlib.h>
#include <string.h>

#define LOGI(...)                                                              \
  __android_log_print(ANDROID_LOG_INFO, "WawonaRenderer", __VA_ARGS__)
#define LOGE(...)                                                              \
  __android_log_print(ANDROID_LOG_ERROR, "WawonaRenderer", __VA_ARGS__)

#ifndef MAX_CACHED_BUFFERS
#define MAX_CACHED_BUFFERS 64
#endif

typedef struct CachedTexture {
  uint64_t buffer_id;
  VkImage image;
  VkImageView image_view;
  VkDeviceMemory memory;
  uint32_t width;
  uint32_t height;
  VkBuffer staging_buffer;
  VkDeviceMemory staging_memory;
  size_t staging_size;
  int in_use;
} CachedTexture;

typedef struct RendererAndroid {
  VkDevice device;
  VkPhysicalDevice physical_device;
  VkRenderPass render_pass;
  VkPipeline pipeline;
  VkPipelineLayout pipeline_layout;
  VkDescriptorSetLayout descriptor_set_layout;
  VkDescriptorPool descriptor_pool;
  VkSampler sampler;
  VkBuffer vertex_buffer;
  VkDeviceMemory vertex_buffer_memory;
  CachedTexture cache[MAX_CACHED_BUFFERS];
  uint32_t extent_width;
  uint32_t extent_height;
} RendererAndroid;

static RendererAndroid *s_renderer = NULL;

/* Vertex data: position (x,y) + texcoord (u,v) for a fullscreen quad
 * Two triangles: (0,0)-(1,0)-(0,1) and (1,0)-(1,1)-(0,1) */
static const float g_quad_vertices[] = {
    /* pos      texcoord */
    0, 0, 0, 0, 1, 0, 1, 0, 0, 1, 0, 1, 1, 1, 1, 1,
};
static const uint16_t g_quad_indices[] = {0, 1, 2, 1, 3, 2};

static VkFormat shm_format_to_vk(uint32_t wl_format) {
  /* WL_SHM_FORMAT_ARGB8888 = 0, XRGB8888 = 1 - both 32bpp BGRA in memory on
   * little-endian */
  (void)wl_format;
  return VK_FORMAT_B8G8R8A8_UNORM;
}

int renderer_android_init(void) {
  LOGI("Android renderer init (buffer cache + quad pipeline)");
  return 0;
}

void renderer_android_cleanup(void) {
  if (s_renderer) {
    free(s_renderer);
    s_renderer = NULL;
  }
  LOGI("Android renderer cleanup");
}

/* Create the quad pipeline - call from android_jni after device and render pass
 * exist */
int renderer_android_create_pipeline(
    VkDevice device, VkPhysicalDevice physical_device, VkRenderPass render_pass,
    uint32_t queue_family, uint32_t extent_width, uint32_t extent_height) {
  if (s_renderer) {
    LOGI("Renderer pipeline already created");
    return 0;
  }

  s_renderer = calloc(1, sizeof(RendererAndroid));
  if (!s_renderer) {
    LOGE("Failed to allocate renderer");
    return -1;
  }

  s_renderer->device = device;
  s_renderer->physical_device = physical_device;
  s_renderer->render_pass = render_pass;
  s_renderer->extent_width = extent_width;
  s_renderer->extent_height = extent_height;

  VkResult res;

  /* Create shader modules from embedded SPIR-V */
  VkShaderModule vert_module, frag_module;
  VkShaderModuleCreateInfo vert_ci = {
      .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
      .codeSize = g_quad_vert_spv_len,
      .pCode = (const uint32_t *)g_quad_vert_spv,
  };
  res = vkCreateShaderModule(device, &vert_ci, NULL, &vert_module);
  if (res != VK_SUCCESS) {
    LOGE("Failed to create vertex shader module: %d", res);
    goto err;
  }

  VkShaderModuleCreateInfo frag_ci = {
      .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
      .codeSize = g_quad_frag_spv_len,
      .pCode = (const uint32_t *)g_quad_frag_spv,
  };
  res = vkCreateShaderModule(device, &frag_ci, NULL, &frag_module);
  if (res != VK_SUCCESS) {
    LOGE("Failed to create fragment shader module: %d", res);
    vkDestroyShaderModule(device, vert_module, NULL);
    goto err;
  }

  /* Push constants: 12 floats = 48 bytes */
  VkPushConstantRange push_range = {
      .stageFlags = VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT,
      .offset = 0,
      .size = 48,
  };

  /* Descriptor set layout: single combined image sampler */
  VkDescriptorSetLayoutBinding sampler_binding = {
      .binding = 0,
      .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
      .descriptorCount = 1,
      .stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT,
  };
  VkDescriptorSetLayoutCreateInfo dsl_ci = {
      .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
      .bindingCount = 1,
      .pBindings = &sampler_binding,
  };
  res = vkCreateDescriptorSetLayout(device, &dsl_ci, NULL,
                                    &s_renderer->descriptor_set_layout);
  if (res != VK_SUCCESS) {
    LOGE("Failed to create descriptor set layout: %d", res);
    vkDestroyShaderModule(device, frag_module, NULL);
    vkDestroyShaderModule(device, vert_module, NULL);
    goto err;
  }

  VkPipelineLayoutCreateInfo pl_ci = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
      .setLayoutCount = 1,
      .pSetLayouts = &s_renderer->descriptor_set_layout,
      .pushConstantRangeCount = 1,
      .pPushConstantRanges = &push_range,
  };
  res = vkCreatePipelineLayout(device, &pl_ci, NULL,
                               &s_renderer->pipeline_layout);
  if (res != VK_SUCCESS) {
    LOGE("Failed to create pipeline layout: %d", res);
    vkDestroyDescriptorSetLayout(device, s_renderer->descriptor_set_layout,
                                 NULL);
    vkDestroyShaderModule(device, frag_module, NULL);
    vkDestroyShaderModule(device, vert_module, NULL);
    goto err;
  }

  /* Create sampler */
  VkSamplerCreateInfo samp_ci = {
      .sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
      .magFilter = VK_FILTER_LINEAR,
      .minFilter = VK_FILTER_LINEAR,
      .addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
      .addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
      .addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
  };
  res = vkCreateSampler(device, &samp_ci, NULL, &s_renderer->sampler);
  if (res != VK_SUCCESS) {
    LOGE("Failed to create sampler: %d", res);
    vkDestroyPipelineLayout(device, s_renderer->pipeline_layout, NULL);
    vkDestroyDescriptorSetLayout(device, s_renderer->descriptor_set_layout,
                                 NULL);
    vkDestroyShaderModule(device, frag_module, NULL);
    vkDestroyShaderModule(device, vert_module, NULL);
    goto err;
  }

  /* Descriptor pool - need at least one set per simultaneous texture */
  VkDescriptorPoolSize pool_size = {
      .type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
      .descriptorCount = MAX_CACHED_BUFFERS,
  };
  VkDescriptorPoolCreateInfo dp_ci = {
      .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
      .maxSets = MAX_CACHED_BUFFERS,
      .poolSizeCount = 1,
      .pPoolSizes = &pool_size,
  };
  res = vkCreateDescriptorPool(device, &dp_ci, NULL,
                               &s_renderer->descriptor_pool);
  if (res != VK_SUCCESS) {
    LOGE("Failed to create descriptor pool: %d", res);
    vkDestroySampler(device, s_renderer->sampler, NULL);
    vkDestroyPipelineLayout(device, s_renderer->pipeline_layout, NULL);
    vkDestroyDescriptorSetLayout(device, s_renderer->descriptor_set_layout,
                                 NULL);
    vkDestroyShaderModule(device, frag_module, NULL);
    vkDestroyShaderModule(device, vert_module, NULL);
    goto err;
  }

  /* Pipeline */
  VkPipelineShaderStageCreateInfo stages[2] = {
      {
          .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
          .stage = VK_SHADER_STAGE_VERTEX_BIT,
          .module = vert_module,
          .pName = "main",
      },
      {
          .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
          .stage = VK_SHADER_STAGE_FRAGMENT_BIT,
          .module = frag_module,
          .pName = "main",
      },
  };

  VkVertexInputBindingDescription binding = {
      .binding = 0,
      .stride = 4 * sizeof(float),
      .inputRate = VK_VERTEX_INPUT_RATE_VERTEX,
  };
  VkVertexInputAttributeDescription attrs[2] = {
      {.location = 0,
       .binding = 0,
       .format = VK_FORMAT_R32G32_SFLOAT,
       .offset = 0},
      {.location = 1,
       .binding = 0,
       .format = VK_FORMAT_R32G32_SFLOAT,
       .offset = 2 * sizeof(float)},
  };
  VkPipelineVertexInputStateCreateInfo vi = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
      .vertexBindingDescriptionCount = 1,
      .pVertexBindingDescriptions = &binding,
      .vertexAttributeDescriptionCount = 2,
      .pVertexAttributeDescriptions = attrs,
  };

  VkPipelineInputAssemblyStateCreateInfo ia = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
      .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
  };

  VkPipelineViewportStateCreateInfo vp = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
      .viewportCount = 1,
      .scissorCount = 1,
  };

  VkPipelineRasterizationStateCreateInfo rs = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
      .polygonMode = VK_POLYGON_MODE_FILL,
      .cullMode = VK_CULL_MODE_NONE,
      .frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE,
  };

  VkPipelineMultisampleStateCreateInfo ms = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
      .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT,
  };

  VkPipelineColorBlendAttachmentState blend_attach = {
      .blendEnable = VK_TRUE,
      .srcColorBlendFactor = VK_BLEND_FACTOR_ONE,
      .dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
      .colorBlendOp = VK_BLEND_OP_ADD,
      .srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE,
      .dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
      .alphaBlendOp = VK_BLEND_OP_ADD,
      .colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                        VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT,
  };
  VkPipelineColorBlendStateCreateInfo cb = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
      .attachmentCount = 1,
      .pAttachments = &blend_attach,
  };

  VkDynamicState dyn_states[] = {VK_DYNAMIC_STATE_VIEWPORT,
                                 VK_DYNAMIC_STATE_SCISSOR};
  VkPipelineDynamicStateCreateInfo dyn = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
      .dynamicStateCount = 2,
      .pDynamicStates = dyn_states,
  };

  VkGraphicsPipelineCreateInfo gp_ci = {
      .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
      .stageCount = 2,
      .pStages = stages,
      .pVertexInputState = &vi,
      .pInputAssemblyState = &ia,
      .pViewportState = &vp,
      .pRasterizationState = &rs,
      .pMultisampleState = &ms,
      .pColorBlendState = &cb,
      .pDynamicState = &dyn,
      .layout = s_renderer->pipeline_layout,
      .renderPass = render_pass,
      .subpass = 0,
  };
  res = vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1, &gp_ci, NULL,
                                  &s_renderer->pipeline);
  vkDestroyShaderModule(device, vert_module, NULL);
  vkDestroyShaderModule(device, frag_module, NULL);
  if (res != VK_SUCCESS) {
    LOGE("Failed to create graphics pipeline: %d", res);
    vkDestroyDescriptorPool(device, s_renderer->descriptor_pool, NULL);
    vkDestroySampler(device, s_renderer->sampler, NULL);
    vkDestroyPipelineLayout(device, s_renderer->pipeline_layout, NULL);
    vkDestroyDescriptorSetLayout(device, s_renderer->descriptor_set_layout,
                                 NULL);
    goto err;
  }

  /* Create vertex + index buffer for the quad */
  VkBufferCreateInfo buf_ci = {
      .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
      .size = sizeof(g_quad_vertices) + sizeof(g_quad_indices),
      .usage = VK_BUFFER_USAGE_VERTEX_BUFFER_BIT |
               VK_BUFFER_USAGE_INDEX_BUFFER_BIT |
               VK_BUFFER_USAGE_TRANSFER_DST_BIT,
      .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
  };
  res = vkCreateBuffer(device, &buf_ci, NULL, &s_renderer->vertex_buffer);
  if (res != VK_SUCCESS) {
    LOGE("Failed to create vertex buffer: %d", res);
    vkDestroyPipeline(device, s_renderer->pipeline, NULL);
    vkDestroyDescriptorPool(device, s_renderer->descriptor_pool, NULL);
    vkDestroySampler(device, s_renderer->sampler, NULL);
    vkDestroyPipelineLayout(device, s_renderer->pipeline_layout, NULL);
    vkDestroyDescriptorSetLayout(device, s_renderer->descriptor_set_layout,
                                 NULL);
    goto err;
  }

  VkMemoryRequirements mem_req;
  vkGetBufferMemoryRequirements(device, s_renderer->vertex_buffer, &mem_req);
  VkMemoryAllocateInfo mem_ai = {
      .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
      .allocationSize = mem_req.size,
      .memoryTypeIndex = 0, /* Will fix below - need heap type */
  };

  VkPhysicalDeviceMemoryProperties mem_props;
  vkGetPhysicalDeviceMemoryProperties(physical_device, &mem_props);
  for (uint32_t i = 0; i < mem_props.memoryTypeCount; i++) {
    if ((mem_req.memoryTypeBits & (1u << i)) &&
        (mem_props.memoryTypes[i].propertyFlags &
         VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) {
      mem_ai.memoryTypeIndex = i;
      break;
    }
  }

  res = vkAllocateMemory(device, &mem_ai, NULL,
                         &s_renderer->vertex_buffer_memory);
  if (res != VK_SUCCESS) {
    LOGE("Failed to allocate vertex buffer memory: %d", res);
    vkDestroyBuffer(device, s_renderer->vertex_buffer, NULL);
    vkDestroyPipeline(device, s_renderer->pipeline, NULL);
    vkDestroyDescriptorPool(device, s_renderer->descriptor_pool, NULL);
    vkDestroySampler(device, s_renderer->sampler, NULL);
    vkDestroyPipelineLayout(device, s_renderer->pipeline_layout, NULL);
    vkDestroyDescriptorSetLayout(device, s_renderer->descriptor_set_layout,
                                 NULL);
    goto err;
  }
  vkBindBufferMemory(device, s_renderer->vertex_buffer,
                     s_renderer->vertex_buffer_memory, 0);

  /* Map and upload vertex data */
  void *ptr;
  res = vkMapMemory(device, s_renderer->vertex_buffer_memory, 0, VK_WHOLE_SIZE,
                    0, &ptr);
  if (res == VK_SUCCESS) {
    memcpy(ptr, g_quad_vertices, sizeof(g_quad_vertices));
    memcpy((char *)ptr + sizeof(g_quad_vertices), g_quad_indices,
           sizeof(g_quad_indices));
    vkUnmapMemory(device, s_renderer->vertex_buffer_memory);
  }

  LOGI("Android renderer pipeline created");
  return 0;

err:
  if (s_renderer) {
    free(s_renderer);
    s_renderer = NULL;
  }
  return -1;
}

void renderer_android_destroy_pipeline(void) {
  if (!s_renderer || !s_renderer->device)
    return;

  VkDevice dev = s_renderer->device;
  for (int i = 0; i < MAX_CACHED_BUFFERS; i++) {
    CachedTexture *t = &s_renderer->cache[i];
    if (t->image_view != VK_NULL_HANDLE)
      vkDestroyImageView(dev, t->image_view, NULL);
    if (t->image != VK_NULL_HANDLE)
      vkDestroyImage(dev, t->image, NULL);
    if (t->memory != VK_NULL_HANDLE)
      vkFreeMemory(dev, t->memory, NULL);
    if (t->staging_buffer != VK_NULL_HANDLE)
      vkDestroyBuffer(dev, t->staging_buffer, NULL);
    if (t->staging_memory != VK_NULL_HANDLE)
      vkFreeMemory(dev, t->staging_memory, NULL);
  }
  if (s_renderer->vertex_buffer != VK_NULL_HANDLE)
    vkDestroyBuffer(dev, s_renderer->vertex_buffer, NULL);
  if (s_renderer->vertex_buffer_memory != VK_NULL_HANDLE)
    vkFreeMemory(dev, s_renderer->vertex_buffer_memory, NULL);
  if (s_renderer->pipeline != VK_NULL_HANDLE)
    vkDestroyPipeline(dev, s_renderer->pipeline, NULL);
  if (s_renderer->descriptor_pool != VK_NULL_HANDLE)
    vkDestroyDescriptorPool(dev, s_renderer->descriptor_pool, NULL);
  if (s_renderer->sampler != VK_NULL_HANDLE)
    vkDestroySampler(dev, s_renderer->sampler, NULL);
  if (s_renderer->pipeline_layout != VK_NULL_HANDLE)
    vkDestroyPipelineLayout(dev, s_renderer->pipeline_layout, NULL);
  if (s_renderer->descriptor_set_layout != VK_NULL_HANDLE)
    vkDestroyDescriptorSetLayout(dev, s_renderer->descriptor_set_layout, NULL);

  free(s_renderer);
  s_renderer = NULL;
  LOGI("Android renderer pipeline destroyed");
}

/* Upload SHM buffer to a VkImage and cache it. cmd_buf must be recording.
 * Returns 0 on success. */
int renderer_android_cache_buffer(VkCommandBuffer cmd_buf, uint64_t buffer_id,
                                  uint32_t width, uint32_t height,
                                  uint32_t stride, uint32_t format,
                                  const uint8_t *pixels, size_t size) {
  if (!s_renderer || !pixels || width == 0 || height == 0)
    return -1;

  VkDevice dev = s_renderer->device;
  VkPhysicalDevice pd = s_renderer->physical_device;
  VkResult res;

  /* Find existing or empty slot */
  CachedTexture *slot = NULL;
  for (int i = 0; i < MAX_CACHED_BUFFERS; i++) {
    if (s_renderer->cache[i].buffer_id == buffer_id) {
      slot = &s_renderer->cache[i];
      break;
    }
    if (s_renderer->cache[i].image == VK_NULL_HANDLE) {
      slot = &s_renderer->cache[i];
      break;
    }
  }
  if (!slot) {
    LOGE("Buffer cache full");
    return -1;
  }

  /* If reusing, destroy old image resources if size changed */
  if (slot->width != width || slot->height != height) {
    if (slot->image_view != VK_NULL_HANDLE)
      vkDestroyImageView(dev, slot->image_view, NULL);
    if (slot->image != VK_NULL_HANDLE)
      vkDestroyImage(dev, slot->image, NULL);
    if (slot->memory != VK_NULL_HANDLE)
      vkFreeMemory(dev, slot->memory, NULL);
    slot->image_view = VK_NULL_HANDLE;
    slot->image = VK_NULL_HANDLE;
    slot->memory = VK_NULL_HANDLE;
  }

  size_t expected_size = (size_t)height * stride;
  if (size < expected_size) {
    LOGE("Buffer size %zu < expected %zu", size, expected_size);
    return -1;
  }

  VkFormat vk_fmt = shm_format_to_vk(format);
  VkImageCreateInfo img_ci = {
      .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
      .imageType = VK_IMAGE_TYPE_2D,
      .format = vk_fmt,
      .extent = {width, height, 1},
      .mipLevels = 1,
      .arrayLayers = 1,
      .samples = VK_SAMPLE_COUNT_1_BIT,
      .tiling = VK_IMAGE_TILING_OPTIMAL,
      .usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
      .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
  };
  if (slot->image == VK_NULL_HANDLE) {
    res = vkCreateImage(dev, &img_ci, NULL, &slot->image);
    if (res != VK_SUCCESS) {
      LOGE("Failed to create texture image: %d", res);
      return -1;
    }

    VkMemoryRequirements mem_req;
    vkGetImageMemoryRequirements(dev, slot->image, &mem_req);
    VkPhysicalDeviceMemoryProperties mem_props;
    vkGetPhysicalDeviceMemoryProperties(pd, &mem_props);
    uint32_t mem_type = 0;
    for (uint32_t i = 0; i < mem_props.memoryTypeCount; i++) {
      if ((mem_req.memoryTypeBits & (1u << i)) &&
          (mem_props.memoryTypes[i].propertyFlags &
           VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) {
        mem_type = i;
        break;
      }
    }

    VkMemoryAllocateInfo mem_ai = {
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = mem_req.size,
        .memoryTypeIndex = mem_type,
    };
    res = vkAllocateMemory(dev, &mem_ai, NULL, &slot->memory);
    if (res != VK_SUCCESS) {
      LOGE("Failed to allocate image memory: %d", res);
      vkDestroyImage(dev, slot->image, NULL);
      slot->image = VK_NULL_HANDLE;
      return -1;
    }
    vkBindImageMemory(dev, slot->image, slot->memory, 0);

    VkImageViewCreateInfo iv_ci = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = slot->image,
        .viewType = VK_IMAGE_VIEW_TYPE_2D,
        .format = vk_fmt,
        .subresourceRange =
            {
                .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
    };
    res = vkCreateImageView(dev, &iv_ci, NULL, &slot->image_view);
    if (res != VK_SUCCESS) {
      LOGE("Failed to create image view: %d", res);
      vkFreeMemory(dev, slot->memory, NULL);
      vkDestroyImage(dev, slot->image, NULL);
      slot->image = VK_NULL_HANDLE;
      slot->memory = VK_NULL_HANDLE;
      return -1;
    }
  }

  /* Create staging buffer and upload - requires command buffer from caller.
   * We'll need to export an upload function that takes a command buffer.
   * For now, use a simplified path: create a host-visible staging buffer,
   * copy pixels, then we need a one-time copy. The android_jni will need
   * to call an "upload" with its command buffer. Let me add
   * renderer_android_upload_pending which takes a VkCommandBuffer and does
   * the copy. Actually the cache_buffer is called from the frame callback
   * context where we have a command buffer. So we need to pass it.
   * Refactor: cache_buffer just stores the buffer info; a separate
   * renderer_android_upload_buffer(cmdBuf, buffer_id, ...) does the actual
   * upload. Or we can have cache_buffer take the command buffer.
   */
  /* For immediate use we need to copy. The simplest: require the caller to
   * pass a command buffer. Change signature to cache_buffer(cmdBuf, ...).
   */
  slot->buffer_id = buffer_id;
  slot->width = width;
  slot->height = height;
  slot->in_use = 1;

  /* Staging buffer for pixel upload - reuse if size matches */
  size_t buffer_size = (size_t)height * stride;
  if (slot->staging_buffer == VK_NULL_HANDLE ||
      slot->staging_size < buffer_size) {
    if (slot->staging_buffer != VK_NULL_HANDLE)
      vkDestroyBuffer(dev, slot->staging_buffer, NULL);
    if (slot->staging_memory != VK_NULL_HANDLE)
      vkFreeMemory(dev, slot->staging_memory, NULL);

    VkBufferCreateInfo staging_ci = {
        .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = buffer_size,
        .usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
    };
    res = vkCreateBuffer(dev, &staging_ci, NULL, &slot->staging_buffer);
    if (res != VK_SUCCESS)
      return -1;

    VkMemoryRequirements staging_req;
    vkGetBufferMemoryRequirements(dev, slot->staging_buffer, &staging_req);
    VkPhysicalDeviceMemoryProperties mem_props_staging;
    vkGetPhysicalDeviceMemoryProperties(pd, &mem_props_staging);
    uint32_t staging_type = 0;
    for (uint32_t i = 0; i < mem_props_staging.memoryTypeCount; i++) {
      if ((staging_req.memoryTypeBits & (1u << i)) &&
          (mem_props_staging.memoryTypes[i].propertyFlags &
           VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) {
        staging_type = i;
        break;
      }
    }
    VkMemoryAllocateInfo staging_mem_ai = {
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = staging_req.size,
        .memoryTypeIndex = staging_type,
    };
    res = vkAllocateMemory(dev, &staging_mem_ai, NULL, &slot->staging_memory);
    if (res != VK_SUCCESS) {
      vkDestroyBuffer(dev, slot->staging_buffer, NULL);
      slot->staging_buffer = VK_NULL_HANDLE;
      return -1;
    }
    vkBindBufferMemory(dev, slot->staging_buffer, slot->staging_memory, 0);
    slot->staging_size = buffer_size;
  }

  void *map_ptr;
  res = vkMapMemory(dev, slot->staging_memory, 0, buffer_size, 0, &map_ptr);
  if (res == VK_SUCCESS) {
    memcpy(map_ptr, pixels, buffer_size);
    vkUnmapMemory(dev, slot->staging_memory);
  } else {
    return -1;
  }

  /* Transition image to transfer dst, copy, transition to shader read */
  VkImageMemoryBarrier barrier_to_dst = {
      .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
      .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED,
      .newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
      .srcAccessMask = 0,
      .dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT,
      .image = slot->image,
      .subresourceRange =
          {
              .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
              .levelCount = 1,
              .layerCount = 1,
          },
  };
  vkCmdPipelineBarrier(cmd_buf, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
                       VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1,
                       &barrier_to_dst);

  VkBufferImageCopy region = {
      .bufferOffset = 0,
      .bufferRowLength = stride / 4,
      .bufferImageHeight = height,
      .imageSubresource =
          {
              .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
              .layerCount = 1,
          },
      .imageExtent = {width, height, 1},
  };
  vkCmdCopyBufferToImage(cmd_buf, slot->staging_buffer, slot->image,
                         VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

  VkImageMemoryBarrier barrier_to_read = {
      .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
      .oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
      .newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
      .srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT,
      .dstAccessMask = VK_ACCESS_SHADER_READ_BIT,
      .image = slot->image,
      .subresourceRange =
          {
              .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
              .levelCount = 1,
              .layerCount = 1,
          },
  };
  vkCmdPipelineBarrier(cmd_buf, VK_PIPELINE_STAGE_TRANSFER_BIT,
                       VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, NULL, 0,
                       NULL, 1, &barrier_to_read);

  return 0;
}

/* Get VkImageView for buffer_id, or VK_NULL_HANDLE if not cached */
VkImageView renderer_android_get_texture(uint64_t buffer_id) {
  if (!s_renderer)
    return VK_NULL_HANDLE;
  for (int i = 0; i < MAX_CACHED_BUFFERS; i++) {
    if (s_renderer->cache[i].buffer_id == buffer_id &&
        s_renderer->cache[i].image_view != VK_NULL_HANDLE)
      return s_renderer->cache[i].image_view;
  }
  return VK_NULL_HANDLE;
}

/* Get width/height for buffer_id. Returns 0,0 if not cached. */
static void get_texture_size(uint64_t buffer_id, uint32_t *width,
                             uint32_t *height) {
  *width = 0;
  *height = 0;
  if (!s_renderer)
    return;
  for (int i = 0; i < MAX_CACHED_BUFFERS; i++) {
    if (s_renderer->cache[i].buffer_id == buffer_id &&
        s_renderer->cache[i].image_view != VK_NULL_HANDLE) {
      *width = s_renderer->cache[i].width;
      *height = s_renderer->cache[i].height;
      return;
    }
  }
}

/* Evict buffer from cache when frame presented */
void renderer_android_evict_buffer(uint64_t buffer_id) {
  if (!s_renderer)
    return;
  for (int i = 0; i < MAX_CACHED_BUFFERS; i++) {
    if (s_renderer->cache[i].buffer_id == buffer_id) {
      s_renderer->cache[i].in_use = 0;
      /* Optionally reclaim immediately; for now keep for reuse */
      break;
    }
  }
}

/* Reset descriptor pool so we can reallocate sets each frame */
static void reset_descriptor_pool(void) {
  if (!s_renderer || s_renderer->descriptor_pool == VK_NULL_HANDLE)
    return;
  vkResetDescriptorPool(s_renderer->device, s_renderer->descriptor_pool, 0);
}

/* Draw scene nodes as textured quads. Assumes render pass has been begun.
 * Requires VkCommandBuffer, viewport/scissor set. */
void renderer_android_draw_quads(VkCommandBuffer cmd_buf,
                                 const struct CRenderNode *nodes,
                                 size_t node_count, uint32_t extent_width,
                                 uint32_t extent_height) {
  if (!s_renderer || !nodes || node_count == 0)
    return;

  reset_descriptor_pool();

  vkCmdBindPipeline(cmd_buf, VK_PIPELINE_BIND_POINT_GRAPHICS,
                    s_renderer->pipeline);
  vkCmdBindVertexBuffers(cmd_buf, 0, 1, &s_renderer->vertex_buffer,
                         (VkDeviceSize[]){0});
  vkCmdBindIndexBuffer(cmd_buf, s_renderer->vertex_buffer,
                       sizeof(g_quad_vertices), VK_INDEX_TYPE_UINT16);

  float ext_x = (float)extent_width;
  float ext_y = (float)extent_height;
  if (ext_x < 1)
    ext_x = 1;
  if (ext_y < 1)
    ext_y = 1;

  for (size_t i = 0; i < node_count; i++) {
    const struct CRenderNode *n = &nodes[i];
    VkImageView view = renderer_android_get_texture(n->buffer_id);
    if (view == VK_NULL_HANDLE)
      continue;

    float pc[12] = {n->x,
                    n->y,
                    n->width,
                    n->height,
                    ext_x,
                    ext_y,
                    n->opacity,
                    0,
                    n->content_rect_x,
                    n->content_rect_y,
                    n->content_rect_w,
                    n->content_rect_h};
    vkCmdPushConstants(
        cmd_buf, s_renderer->pipeline_layout,
        VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0, 48, pc);

    /* Use a descriptor set - we need to create/update per draw or use a simpler
     * path. Vulkan requires a descriptor set for the sampler. We can use
     * vkCmdPushConstants for the transform but the fragment shader needs
     * the texture. Options:
     * 1. Create a descriptor set per texture (expensive)
     * 2. Use a descriptor set array and bind by index
     * 3. Use VK_EXT_descriptor_indexing / bindless (complex)
     * Simplest: create descriptor set per draw from the pool. We need
     * VkDescriptorSet with the image view. */
    VkDescriptorSet set;
    VkDescriptorSetAllocateInfo alloc_info = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = s_renderer->descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &s_renderer->descriptor_set_layout,
    };
    VkResult res =
        vkAllocateDescriptorSets(s_renderer->device, &alloc_info, &set);
    if (res != VK_SUCCESS)
      continue;

    VkDescriptorImageInfo img_info = {
        .sampler = s_renderer->sampler,
        .imageView = view,
        .imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    };
    VkWriteDescriptorSet write = {
        .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = set,
        .dstBinding = 0,
        .dstArrayElement = 0,
        .descriptorCount = 1,
        .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = &img_info,
    };
    vkUpdateDescriptorSets(s_renderer->device, 1, &write, 0, NULL);
    vkCmdBindDescriptorSets(cmd_buf, VK_PIPELINE_BIND_POINT_GRAPHICS,
                            s_renderer->pipeline_layout, 0, 1, &set, 0, NULL);

    vkCmdDrawIndexed(cmd_buf, 6, 1, 0, 0, 0);
  }
}

/* Draw cursor as final textured quad. Same pipeline as scene nodes. */
void renderer_android_draw_cursor(VkCommandBuffer cmd_buf,
                                  uint64_t cursor_buffer_id, float cursor_x,
                                  float cursor_y, float cursor_hotspot_x,
                                  float cursor_hotspot_y, uint32_t extent_width,
                                  uint32_t extent_height) {
  if (!s_renderer || cursor_buffer_id == 0)
    return;

  uint32_t cw, ch;
  get_texture_size(cursor_buffer_id, &cw, &ch);
  if (cw == 0 || ch == 0)
    return;

  VkImageView view = renderer_android_get_texture(cursor_buffer_id);
  if (view == VK_NULL_HANDLE)
    return;

  /* Top-left of cursor quad = hotspot position minus hotspot offset */
  float pos_x = cursor_x - cursor_hotspot_x;
  float pos_y = cursor_y - cursor_hotspot_y;
  float ext_x = (float)extent_width;
  float ext_y = (float)extent_height;
  if (ext_x < 1)
    ext_x = 1;
  if (ext_y < 1)
    ext_y = 1;

  float pc[12] = {pos_x, pos_y, (float)cw, (float)ch, ext_x, ext_y,
                  1.0f,  0,     0.0f,      0.0f,      1.0f,  1.0f};
  vkCmdPushConstants(cmd_buf, s_renderer->pipeline_layout,
                     VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT,
                     0, 48, pc);

  VkDescriptorSet set;
  VkDescriptorSetAllocateInfo alloc_info = {
      .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
      .descriptorPool = s_renderer->descriptor_pool,
      .descriptorSetCount = 1,
      .pSetLayouts = &s_renderer->descriptor_set_layout,
  };
  VkResult res =
      vkAllocateDescriptorSets(s_renderer->device, &alloc_info, &set);
  if (res != VK_SUCCESS)
    return;

  VkDescriptorImageInfo img_info = {
      .sampler = s_renderer->sampler,
      .imageView = view,
      .imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
  };
  VkWriteDescriptorSet write = {
      .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
      .dstSet = set,
      .dstBinding = 0,
      .dstArrayElement = 0,
      .descriptorCount = 1,
      .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
      .pImageInfo = &img_info,
  };
  vkUpdateDescriptorSets(s_renderer->device, 1, &write, 0, NULL);
  vkCmdBindDescriptorSets(cmd_buf, VK_PIPELINE_BIND_POINT_GRAPHICS,
                          s_renderer->pipeline_layout, 0, 1, &set, 0, NULL);

  vkCmdBindPipeline(cmd_buf, VK_PIPELINE_BIND_POINT_GRAPHICS,
                    s_renderer->pipeline);
  vkCmdBindVertexBuffers(cmd_buf, 0, 1, &s_renderer->vertex_buffer,
                         (VkDeviceSize[]){0});
  vkCmdBindIndexBuffer(cmd_buf, s_renderer->vertex_buffer,
                       sizeof(g_quad_vertices), VK_INDEX_TYPE_UINT16);
  vkCmdDrawIndexed(cmd_buf, 6, 1, 0, 0, 0);
}

#endif /* __ANDROID__ */
