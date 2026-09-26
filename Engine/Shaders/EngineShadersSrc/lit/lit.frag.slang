import common;

[[vk_binding(2, 0)]]
Sampler2D baseTexture;

// [[vk_binding(1, 2)]]
// Sampler2D roughnessTexture;
//
// [[vk_binding(2, 2)]]
// Sampler2D metallicTexture;

[[vk_binding(3, 0)]]
Sampler2D normalTexture;

struct Camera {
  float3 pos;
};
[[vk_binding(4, 0)]]
ConstantBuffer<Camera> camera;

struct Light {
  float3 pos;
};
[[vk_binding(5, 0)]]
ConstantBuffer<Light> light;

struct Material {
  float4 baseColor;
  float metallic;
  float roughness;
};
[[vk_binding(6, 0)]]
ConstantBuffer<Material> material;

static const float PI = 3.14159265359;

float3 cookTorrance(float3 normal, float3 viewDir, float3 lightDir,
                    float3 baseColor, float3 lightColor) {
  float3 halfwayDir = normalize(viewDir + lightDir);

  // microfacet distribution highlight
  float normDotHalfway = max(dot(normal, halfwayDir), 0.0);

  float roughnessPow4 = pow(material.roughness, 4);
  float highlight =
      roughnessPow4 /
      (PI * pow(pow(normDotHalfway, 2) * (roughnessPow4 - 1) + 1, 2));

  // geometry self shadowing
  const float shadowing = pow(material.roughness + 1, 2) / 8;

  float normDotLight = max(dot(normal, lightDir), 0.0f);
  float normDotView = max(dot(normal, viewDir), 0.0f);

  float lightPathVisibility =
      normDotLight / (normDotLight * (1 - shadowing) + shadowing);
  float cameraPathVisibility =
      normDotView / (normDotView * (1 - shadowing) + shadowing);

  float selfShadowing = lightPathVisibility * cameraPathVisibility;

  // fresnel reflectance
  float3 baseReflectivity =
      lerp(float3(0.04, 0.04, 0.04), baseColor, float3(material.metallic));

  float cameraFacingHalfway = max(dot(viewDir, halfwayDir), 0.0f);
  float3 reflectivitySideways =
      baseReflectivity +
      (1 - baseReflectivity) * pow(1 - cameraFacingHalfway, 5);

  // + 0.0001 avoids div by zero
  float3 specular = (highlight * selfShadowing * reflectivitySideways) /
                    (4 * normDotView * normDotLight + 0.0001);

  float3 diffuseAmount = (1 - reflectivitySideways) * (1 - material.metallic);
  float3 diffuseColor = diffuseAmount * baseColor / PI;

  return (diffuseColor + specular) * lightColor * normDotLight;
}

[shader("fragment")]
float4 fragMain(VSOutput vertIn, float4 screenCoord: SV_Position) : SV_Target {
  float3 lightDir = normalize(light.pos - vertIn.fragPos);
  float3 viewDir = normalize(camera.pos - vertIn.fragPos);

  float3 normal = normalize(vertIn.normal);

  float4 baseColor = material.baseColor * baseTexture.Sample(vertIn.uv);

  float3 lightColor = float3(1.0, 1.0, 1.0);

  float3 ambient = 1.0 * baseColor.rgb;

  float3 result =
      cookTorrance(normal, viewDir, lightDir, baseColor.rgb, lightColor) +
      ambient;

  return float4(result, 1.0);
}
