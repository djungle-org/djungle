import simple_vert;

// Sampler2D texture;

[shader("fragment")]
float4 fragMain(VSOutput vertIn) : SV_Target {
  return float4(0.2, 0.3, 0.4, 1.0);
  // return float4(vertIn.col, 1.0);
  // return texture.Sample(vertIn.texCoord);
}
