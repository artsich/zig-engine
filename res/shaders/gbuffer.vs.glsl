#version 330 core

in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec3 vertexNormal;
in vec4 vertexColor;
in vec4 vertexTangent;

out vec3 fragPosition;
out vec2 fragTexCoord;
out vec4 fragColor;
out mat3 TBN;
out vec3 fragNormal;

uniform mat4 matModel;
uniform mat4 matView;
uniform mat4 matProjection;
uniform mat4 matNormal;

void main() {
    mat3 mt = mat3(matNormal);
    vec3 T = normalize(mt * vertexTangent.xyz);
    vec3 N = normalize(mt * vertexNormal);
    T = normalize(T - dot(T, N) * N);
    vec3 B = cross(N, T);
    TBN = mat3(T, B, N);

    fragNormal = mt * vertexNormal;

    vec4 worldPos = matModel * vec4(vertexPosition, 1.0);
    fragPosition = worldPos.xyz;
    fragTexCoord = vertexTexCoord;
    fragColor = vertexColor;

    gl_Position = matProjection * matView * worldPos;
}
