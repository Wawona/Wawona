#version 450

layout(location = 0) in vec2 inPosition;
layout(location = 1) in vec2 inTexCoord;

layout(location = 0) out vec2 fragTexCoord;

layout(push_constant) uniform PushConstants {
    float pos_x;
    float pos_y;
    float size_x;
    float size_y;
    float extent_x;
    float extent_y;
    float opacity;
    float _pad;
    // Normalized (0..1) content rect within the buffer, mirroring
    // node->content_rect_* on the macOS/iOS renderers (see
    // WWNCompositorBridge.m layer.contentsRect). xdg_surface.set_window_geometry
    // excludes the CSD title bar / border / drop-shadow margin the client
    // paints around its content; without this crop the whole buffer (shadow
    // and all) gets stretched into the content-sized quad, which both leaks
    // the shadow and distorts the aspect ratio.
    float content_rect_x;
    float content_rect_y;
    float content_rect_w;
    float content_rect_h;
} pc;

void main() {
    // Vulkan NDC is Y-down (y=-1 top, y=+1 bottom) and the framebuffer origin is
    // top-left, matching the top-left origin of the Wayland/cairo SHM buffers we
    // sample. Map window-space (0=top .. 1=bottom) straight through, same as X;
    // an OpenGL-style "1.0 - ..." here flips every surface vertically (upside-down
    // text) and mirrors window placement to the wrong half of the screen.
    float ndc_x = (pc.pos_x + inPosition.x * pc.size_x) / pc.extent_x * 2.0 - 1.0;
    float ndc_y = (pc.pos_y + inPosition.y * pc.size_y) / pc.extent_y * 2.0 - 1.0;
    gl_Position = vec4(ndc_x, ndc_y, 0.0, 1.0);

    vec2 rectOrigin = vec2(pc.content_rect_x, pc.content_rect_y);
    vec2 rectSize = vec2(pc.content_rect_w, pc.content_rect_h);
    if (rectSize.x <= 0.0 || rectSize.y <= 0.0) {
        rectOrigin = vec2(0.0, 0.0);
        rectSize = vec2(1.0, 1.0);
    }
    // content_rect_* is in the same top-down, unflipped buffer-normalized
    // space used by node->content_rect_* on the macOS/iOS renderers (see
    // WWNCompositorBridge.m layer.contentsRect): y=0 is the top of the
    // buffer, y=content_rect_y+content_rect_h excludes bottom shadow/border.
    // The uploaded texture rows are in the same top-down order (v=0 samples
    // the buffer's first row), matching the un-flipped NDC mapping above, so
    // no additional V flip is needed here: doing so would sample the crop's
    // bottom rows at the window's top edge, both inverting content vertically
    // and (whenever content_rect_y is non-zero) swapping in decoration rows
    // from outside the intended crop — e.g. showing the CSD titlebar at the
    // window's bottom edge instead of cropping it from the top.
    fragTexCoord = rectOrigin + inTexCoord * rectSize;
}
