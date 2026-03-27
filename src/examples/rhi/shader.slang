struct Vertex {
    float3 position;
};

struct PushConstants {
    Vertex* vertex_buffer;
};
[[vk::push_constant]]
PushConstants push_constants;

struct VertexOutput {
    float4 position: SV_Position;
    float3 color;
};

// static Vertex vertices[4] = {
//     {-1, -1, 0.5},
//     { 1, -1, 0.5},
//     {-1,  1, 0.5},
//     { 1,  1, 0.5},
// };

[shader("vertex")]
VertexOutput vertexMain(uint vertex_id: SV_VertexID) {
    VertexOutput out;
    out.position = float4(push_constants.vertex_buffer[vertex_id].position, 1.0);
    // out.position = float4(vertices[vertex_id].position, 1.0);
    out.color = float3(1.0, 0.0, 1.0);
    return out;
}

[shader("fragment")]
float4 fragmentMain(VertexOutput input): SV_Target {
    return float4(input.color, 1.0);
}

