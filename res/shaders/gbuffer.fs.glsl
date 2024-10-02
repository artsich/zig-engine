#version 330 core

layout (location = 0) out vec3 gPosition;
layout (location = 1) out vec3 gNormal;
layout (location = 2) out vec4 gAlbedoSpec;

in vec3 fragPosition;
in vec2 fragTexCoord;
in vec4 fragColor;
in mat3 TBN;
in vec3 fragNormal;

uniform sampler2D diffuseTexture;
uniform sampler2D specularTexture;
uniform sampler2D normalTexture;

uniform vec4 colDiffuse;

vec3 NormalFromBumpMap() {
    vec3 bumpValue = texture(normalTexture, fragTexCoord).rgb;
    vec3 normal = normalize(TBN * normalize(2.0 * bumpValue - 1.0));
    return normal;
}

void main() {
    gPosition = fragPosition;
    //gNormal = normalize(fragNormal);
    gNormal = NormalFromBumpMap();
    gAlbedoSpec.rgb = texture(diffuseTexture, fragTexCoord).rgb * fragColor.rgb * colDiffuse.rgb;
    gAlbedoSpec.a = texture(specularTexture, fragTexCoord).r;
}
