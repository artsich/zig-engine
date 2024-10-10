#version 330 core

layout (location = 0) in vec3 vertexPosition;
layout (location = 4) in mat4 instanceTransform;

uniform mat4 mvp;

struct Light {
    vec4 lightPos;
    vec4 lightColor;
    float radius;
    float pad0;
    float pad1;
    float pad2;
};

layout (std140) uniform PointLights {
    Light lights[100];  // Массив из 100 источников света
};

out vec3 lightPos;
out vec3 lightColor;
out float radius;

void main() {
    lightPos = lights[gl_InstanceID].lightPos.xyz;
    lightColor = lights[gl_InstanceID].lightColor.rgb;
    radius = lights[gl_InstanceID].radius;

    gl_Position = (mvp * instanceTransform) * vec4(vertexPosition, 1.0);
}
