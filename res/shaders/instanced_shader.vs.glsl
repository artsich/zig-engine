#version 330 core

layout (location = 0) in vec3 vertexPosition;
layout (location = 4) in mat4 instanceTransform;

uniform mat4 mvp;

void main() {
    gl_Position = (mvp * instanceTransform) * vec4(vertexPosition, 1.0);
}
