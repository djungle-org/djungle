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

public struct VSOutput
{
    public float4 pos : SV_Position;
    public float3 col;
    public float2 texCoord;
}

[shader("vertex")]
VSOutput vertMain(VSInput input)
{
    VSOutput output;
    output.pos =
        mul(ubo.proj, mul(ubo.view, mul(ubo.model, float4(input.pos, 0.0, 1.0))));
    output.col      = input.col;
    output.texCoord = input.texCoord;
    return output;
}

Sampler2D texture;

[shader("fragment")]
float4 fragMain(VSOutput vertIn) : SV_Target
{
    // return float4(vertIn.col, 1.0);
    return texture.Sample(vertIn.texCoord);
}
