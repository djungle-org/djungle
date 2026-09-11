import common;

[[vk_binding(0, 2)]]
Sampler2D texture;

[shader("fragment")]
float4 fragMain(VSOutput vertIn, float4 screenCoord: SV_Position) : SV_Target {
  float4 baseColor = texture.Sample(vertIn.uv) * vertIn.col;

  if (baseColor.a < 0.1) {
    discard;
  }

  return baseColor;
}

