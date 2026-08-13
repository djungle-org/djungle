struct UniformBuffer
{
	float4x4 model;
	float4x4 view;
	float4x4 proj;
};
ConstantBuffer<UniformBuffer> ubo;

struct VSInput
{
	float2 pos;
	float3 col;
	float2 texCoord;
};

struct VSOutput
{
	float4 pos : SV_Position;
	float3 col;
	float2 texCoord;
}

[shader("vertex")]
VSOutput main(VSInput input)
{
	VSOutput output;
	output.pos = mul(ubo.proj, mul(ubo.view, mul(ubo.model, float4(input.pos, 0.0, 1.0))));
	output.col = input.col;
	output.texCoord = input.texCoord;
	return output;
}
