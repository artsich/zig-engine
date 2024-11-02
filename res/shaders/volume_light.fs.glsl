#version 330 core

out vec4 finalColor;

uniform sampler2D gPosition;
uniform sampler2D gNormal;
uniform sampler2D gAlbedoSpec;

uniform vec3 camPos;

in vec3 lightPos;
in vec3 lightColor;
in float radius;

float constant = 1.0;
float linear = 0.045;  // Уменьшенное значение
float quadratic = 0.0075;  // Уменьшенное значение

void main() {
    vec2 screenCoord = gl_FragCoord.xy / vec2(textureSize(gPosition, 0));

    vec3 fragPosition = texture(gPosition, screenCoord).rgb;
    vec3 normal = normalize(texture(gNormal, screenCoord).rgb);

    vec3 albedo = texture(gAlbedoSpec, screenCoord).rgb;
    float specularStrength = texture(gAlbedoSpec, screenCoord).a;

    vec3 ambient = albedo * 0.15;

    vec3 lightDir = normalize(lightPos - fragPosition);
    float lightDistance = distance(lightPos, fragPosition);
    if (lightDistance > radius) {
        discard;
    }

    float attenuation = 1.0 / lightDistance; // (constant + linear * lightDistance + quadratic * lightDistance * lightDistance);

    float diff = max(dot(normal, lightDir), 0.0);
    vec3 diffuse = albedo * diff * attenuation;

    vec3 viewDir = normalize(camPos - fragPosition);
    vec3 halfwayDir = normalize(lightDir + viewDir);
    float spec = pow(max(dot(normal, halfwayDir), 0.0), 32.0);
    vec3 specular = vec3(specularStrength * spec * attenuation);

    vec3 result = (ambient * attenuation) + diffuse * lightColor;
    finalColor = vec4(result, 1.);
}
