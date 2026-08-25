import common;

struct Matrices {
  float4x4 model;
  float4x4 view;
  float4x4 proj;
};
[[vk_binding(0, 1)]]
ConstantBuffer<Matrices> matrices;

struct VSInput {
  float2 pos;
  float3 col;
  // float2 texCoord;
};

[shader("vertex")]
VSOutput vertMain(VSInput input) {
  VSOutput output;
  output.pos =
      mul(matrices.proj,
          mul(matrices.view, mul(matrices.model, float4(input.pos, 0.0, 1.0))));

  output.col = input.col;
  // output.texCoord = input.texCoord;
  return output;
}
