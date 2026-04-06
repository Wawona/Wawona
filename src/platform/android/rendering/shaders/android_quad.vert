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
} pc;

void main() {
    float ndc_x = (pc.pos_x + inPosition.x * pc.size_x) / pc.extent_x * 2.0 - 1.0;
    float ndc_y = 1.0 - (pc.pos_y + inPosition.y * pc.size_y) / pc.extent_y * 2.0;
    gl_Position = vec4(ndc_x, ndc_y, 0.0, 1.0);
    fragTexCoord = inTexCoord;
}
