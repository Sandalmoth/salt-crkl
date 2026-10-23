struct Vertex {
    float4 position;
};

struct VertexOutput {
    float4 position: SV_Position;
    float3 color;
};

[shader("vertex")]
VertexOutput vertexMain(
    uint vertex_id: SV_VertexID,
    [[vk::binding(0, 0)]] StructuredBuffer<Vertex> vertices[]
) {
    VertexOutput out;
    out.position = float4(push_constants.vertex_buffer[vertex_id].position.xyz, 1.0);
    out.color = float3(1.0, 0.0, 1.0);
    return out;
}

[shader("fragment")]
float4 fragmentMain(
    VertexOutput input,
): SV_Target {
    return float4(input.color, 1.0);
}

