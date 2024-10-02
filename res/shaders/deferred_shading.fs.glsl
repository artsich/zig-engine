#version 330 core
out vec4 finalColor;

in vec2 texCoord;

uniform sampler2D gPosition;
uniform sampler2D gNormal;
uniform sampler2D gAlbedoSpec;

uniform vec3 camPos;

uniform vec3 lightPos;

float constant = 1.0;
float linear = 0.09;
float quadratic = 0.032;

void main() {
    vec3 fragPosition = texture(gPosition, texCoord).rgb;
    vec3 normal = normalize(texture(gNormal, texCoord).rgb);

    vec3 albedo = texture(gAlbedoSpec, texCoord).rgb;
    float specularStrength = texture(gAlbedoSpec, texCoord).a;

    vec3 abmient = albedo * 0.2;

    vec3 lightDir = normalize(lightPos - fragPosition);
    float lightDistance = distance(lightPos, fragPosition);

    float attenuation = 1.0 / (constant + linear * lightDistance + quadratic * lightDistance * lightDistance);

    float diff = max(dot(normal, lightDir), 0.0);
    vec3 diffuse = albedo * diff * attenuation;

    vec3 viewDir = normalize(camPos - fragPosition);
    vec3 halfwayDir = normalize(lightDir + viewDir);
    float spec = pow(max(dot(normal, halfwayDir), 0.0), 32.0);
    vec3 specular = vec3(specularStrength * spec * attenuation);

    vec3 result = abmient + diffuse + specular;
    finalColor = vec4(result, 1.0);
}
