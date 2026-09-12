import common;

[[vk_binding(0, 2)]]
Sampler2D texture;

struct Camera {
  float3 pos;
};
[[vk_binding(0, 3)]]
ConstantBuffer<Camera> camera;

struct Light {
  float3 pos;
};
[[vk_binding(1, 3)]]
ConstantBuffer<Light> light;

[shader("fragment")]
float4 fragMain(VSOutput vertIn, float4 screenCoord: SV_Position) : SV_Target {
  float3 lightColor = float3(1.0f, 1.0f, 1.0f);
  float3 lightDir = normalize(light.pos - vertIn.fragPos);

  // ambient lighting
  float ambientStrength = 0.1;
  float3 ambient = ambientStrength * lightColor;

  // diffuse lighting
  float3 normal = normalize(vertIn.normal);
  float diffuseVal = max(dot(normal, lightDir), 0.0f);
  float3 diffuse = diffuseVal * lightColor;

  // specular highlights
  float specularStrength = 0.5;
  float3 viewDir = normalize(camera.pos - vertIn.fragPos);
  float3 reflectDir = reflect(-lightDir, normal);
  float specularVal = pow(max(dot(viewDir, reflectDir), 0.0), 32);
  float3 specular = specularStrength * specularVal * lightColor;

  float3 result = (ambient + diffuse + specular) * vertIn.col.rgb;

  float4 baseColor = texture.Sample(vertIn.uv) * float4(result, 1.0f);

  if (baseColor.a < 0.1) {
    discard;
  }

  return baseColor;
}

