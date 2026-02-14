struct VertexOutput {
    float4 position: SV_Position;
    float3 color;
};

[shader("vertex")]
VertexOutput vertexMain(uint vertex_id: SV_VertexID) {
    VertexOutput out;
    return out;
}

[shader("fragment")]
float4 fragmentMain(VertexOutput input): SV_Target {
    return float4(input.color, 1.0);
}

