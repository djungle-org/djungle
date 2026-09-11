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
  float4 col;
  float2 uv;
  float3 normal;
};

[shader("vertex")]
VSOutput vertMain(VSInput input) {
  VSOutput output;
  output.pos =
      mul(viewProj.proj,
          mul(viewProj.view, mul(model.model, float4(input.pos, 1.0))));
  output.fragPos = mul(model.model, float4(input.pos, 1.0)).xyz;

  output.col = input.col;
  output.uv = input.uv;
  output.normal = input.normal;
  return output;
}
