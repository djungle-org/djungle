// struct Matrices {
//   float4x4 model;
//   float4x4 view;
//   float4x4 proj;
// };
// ConstantBuffer<Matrices> matrices;

struct VSInput {
  float2 pos;
  float3 col;
  // float2 texCoord;
};

public struct VSOutput {
  public float4 pos : SV_Position;
  public float3 col;
  // public float2 texCoord;
}

[shader("vertex")]
VSOutput vertMain(VSInput input) {
  VSOutput output;
  // output.pos =
  //     mul(matrices.proj,
  //         mul(matrices.view, mul(matrices.model, float4(input.pos,
  //         0.0, 1.0))));

  output.pos = float4(input.pos, 0.0, 1.0);

  output.col = input.col;
  // output.texCoord = input.texCoord;
  return output;
}
