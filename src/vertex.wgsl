struct VertexOut {
    @builtin(position) position_clip: vec4<f32>,
    @location(0) uv: vec2<f32>,
}
  @vertex fn main(
    @location(0) position: vec3<f32>,
    @location(2) uv: vec2<f32>,
) -> VertexOut {
    var output: VertexOut;
    output.position_clip = vec4(position, 1.0);
    output.uv = uv;
    return output;
}
