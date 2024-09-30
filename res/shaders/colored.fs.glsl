#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

uniform vec4 colDiffuse;

void main() {
    finalColor = colDiffuse*fragColor;
}

