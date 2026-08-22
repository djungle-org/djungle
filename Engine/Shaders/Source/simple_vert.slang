struct VSInput {
  float2 pos;
  // float3 col;
  // float2 texCoord;
};

public struct VSOutput {
  public float4 pos : SV_Position;
  public uint vert_idx;
  // public float3 col;
  // public float2 texCoord;
}

[shader("vertex")]
VSOutput vertMain(VSInput input, uint vert_idx: SV_VertexID) {
  VSOutput output;
  output.pos = float4(input.pos * vert_idx, 0.0, 1.0);
  output.vert_idx = vert_idx;
  // output.col = input.col;
  // output.texCoord = input.texCoord;
  return output;
}
