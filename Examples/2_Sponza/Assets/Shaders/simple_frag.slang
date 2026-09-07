import common;

[[vk_binding(0, 2)]]
Sampler2D texture;

[shader("fragment")]
float4 fragMain(VSOutput vertIn, float4 screenCoord: SV_Position) : SV_Target {
  // return float4(1.0, 1.0, 1.0, 1.0);
  // return lerp(float4(vertIn.col, 1.0), texture.Sample(vertIn.uv), 0.5);
  float currentDepth = screenCoord.z;
  // return float4(currentDepth, currentDepth, currentDepth, 1.0);

  float4 baseColor = texture.Sample(vertIn.uv);

  if (baseColor.a < 0.1) {
    discard;
  }

  return baseColor;
}

