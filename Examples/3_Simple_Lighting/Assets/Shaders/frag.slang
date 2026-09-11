import common;

[[vk_binding(0, 2)]]
Sampler2D texture;

[shader("fragment")]
float4 fragMain(VSOutput vertIn, float4 screenCoord: SV_Position) : SV_Target {
  float3 lightColor = float3(1.0f, 1.0f, 1.0f);
  float3 lightPos = normalize(float3(1.0f, 0.2f, 0.4f));
  float3 lightDir = normalize(lightPos - vertIn.fragPos);

  float ambientStrength = 0.1;
  float3 ambient = ambientStrength * lightColor;

  float diffuseStrength = max(dot(vertIn.normal, lightDir), 0.0f);
  float3 diffuse = diffuseStrength * lightColor;

  float3 result = vertIn.col.rgb * (ambient + diffuse);

  float4 baseColor = texture.Sample(vertIn.uv) * float4(result, 1.0f);

  if (baseColor.a < 0.1) {
    discard;
  }

  return baseColor;
}

