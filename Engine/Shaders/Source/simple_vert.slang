import common;

struct ViewProj {
  float4x4 view;
  float4x4 proj;
};
[[vk_binding(0, 1)]]
ConstantBuffer<ViewProj> viewProj;

struct Model {
  float4x4 model;
};
[[vk_binding(1, 1)]]
ConstantBuffer<Model> model;

struct VSInput {
  float3 pos;
  float3 col;
  // float2 texCoord;
};

[shader("vertex")]
VSOutput vertMain(VSInput input) {
  VSOutput output;
  output.pos =
      mul(viewProj.proj,
          mul(viewProj.view, mul(model.model, float4(input.pos, 1.0))));

  output.col = input.col;
  // output.texCoord = input.texCoord;
  return output;
}
