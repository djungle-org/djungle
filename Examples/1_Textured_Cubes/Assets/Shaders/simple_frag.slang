import common;

[[vk_binding(0, 2)]]
Sampler2D texture;

[shader("fragment")]
float4 fragMain(VSOutput vertIn) : SV_Target {
  // return float4(1.0, 1.0, 1.0, 1.0);
  // return lerp(float4(vertIn.col, 1.0), texture.Sample(vertIn.uv), 0.5);
  return texture.Sample(vertIn.uv);
}

