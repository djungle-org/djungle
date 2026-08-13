Sampler2D texture;

[shader("fragment")]
float4 main(VSOutput vertIn) : SV_Target
{
	// return float4(vertIn.col, 1.0);
	return texture.Sample(vertIn.texCoord);
}
