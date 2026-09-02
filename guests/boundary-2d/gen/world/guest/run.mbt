/// Hitch-eye 2D guest: a square travels the screen-border rectangle in NDC.
/// Position from `clocks.now` delta. Vertices are clip-space (no MVP).

const SHADER : String =
  #|struct VSOut {
  #|  @builtin(position) pos : vec4<f32>,
  #|  @location(0) color : vec3<f32>,
  #|}
  #|@vertex
  #|fn vs_main(@location(0) position : vec3<f32>, @location(1) color : vec3<f32>) -> VSOut {
  #|  var out : VSOut;
  #|  out.pos = vec4<f32>(position, 1.0);
  #|  out.color = color;
  #|  return out;
  #|}
  #|@fragment
  #|fn fs_main(@location(0) color : vec3<f32>) -> @location(0) vec4<f32> {
  #|  return vec4<f32>(color, 1.0);
  #|}

fn ff(x : Double) -> Float {
  Float::from_double(x)
}

fn push_vertex(
  buf : FixedArray[Byte],
  i : Int,
  x : Float,
  y : Float,
  r : Float,
  g : Float,
  b : Float,
) -> Int {
  f32_bytes(buf, i, x)
  f32_bytes(buf, i + 4, y)
  f32_bytes(buf, i + 8, ff(0.0))
  f32_bytes(buf, i + 12, r)
  f32_bytes(buf, i + 16, g)
  f32_bytes(buf, i + 20, b)
  i + 24
}

fn push_quad(
  buf : FixedArray[Byte],
  i : Int,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  r : Double,
  g : Double,
  b : Double,
) -> Int {
  let mut o = i
  o = push_vertex(buf, o, ff(x0), ff(y0), ff(r), ff(g), ff(b))
  o = push_vertex(buf, o, ff(x1), ff(y0), ff(r), ff(g), ff(b))
  o = push_vertex(buf, o, ff(x1), ff(y1), ff(r), ff(g), ff(b))
  o = push_vertex(buf, o, ff(x0), ff(y0), ff(r), ff(g), ff(b))
  o = push_vertex(buf, o, ff(x1), ff(y1), ff(r), ff(g), ff(b))
  o = push_vertex(buf, o, ff(x0), ff(y1), ff(r), ff(g), ff(b))
  o
}

// 4 track quads + 1 mover = 30 verts.
const SCENE_VERTEX_COUNT : UInt = 30U
const SCENE_VERTEX_BYTES : UInt64 = 720UL

fn wrap_peri(s : Double, peri : Double) -> Double {
  let mut d = s
  while d >= peri {
    d = d - peri
  }
  while d < 0.0 {
    d = d + peri
  }
  d
}

/// Centerline of the screen rectangle in NDC (y-up). Clockwise from top-left.
fn perimeter_xy(s : Double, left : Double, right : Double, bottom : Double, top : Double) -> (Double, Double) {
  let w = right - left
  let h = top - bottom
  let peri = 2.0 * (w + h)
  let d = wrap_peri(s, peri)
  if d < w {
    (left + d, top)
  } else if d < w + h {
    (right, top - (d - w))
  } else if d < w + h + w {
    (right - (d - w - h), bottom)
  } else {
    (left, bottom + (d - w - h - w))
  }
}

fn push_rotated_rect(
  buf : FixedArray[Byte],
  i : Int,
  cx : Double,
  cy : Double,
  hx : Double,
  hy : Double,
  angle : Double,
) -> Int {
  let (s, c) = sincos_d(angle)
  fn corner(dx : Double, dy : Double) -> (Float, Float) {
    (ff(cx + c * dx - s * dy), ff(cy + s * dx + c * dy))
  }
  let (x0, y0) = corner(0.0 - hx, 0.0 - hy)
  let (x1, y1) = corner(hx, 0.0 - hy)
  let (x2, y2) = corner(hx, hy)
  let (x3, y3) = corner(0.0 - hx, hy)
  let mut o = i
  // Two-tone so a spin hitch is as obvious as the cube's faces.
  o = push_vertex(buf, o, x0, y0, ff(1.0), ff(0.85), ff(0.15))
  o = push_vertex(buf, o, x1, y1, ff(1.0), ff(0.85), ff(0.15))
  o = push_vertex(buf, o, x2, y2, ff(1.0), ff(0.85), ff(0.15))
  o = push_vertex(buf, o, x0, y0, ff(0.2), ff(0.85), ff(1.0))
  o = push_vertex(buf, o, x2, y2, ff(0.2), ff(0.85), ff(1.0))
  o = push_vertex(buf, o, x3, y3, ff(0.2), ff(0.85), ff(1.0))
  o
}

fn scene_vertices(cx : Double, cy : Double, hx : Double, hy : Double, angle : Double) -> FixedArray[Byte] {
  let buf = FixedArray::make(30 * 24, b'\x00')
  let mut i = 0
  let left = -0.90
  let right = 0.90
  let bottom = -0.90
  let top = 0.90
  let th = 0.018
  // Track (dim). Mover (hot magenta) last so it draws on top with no depth.
  i = push_quad(buf, i, left, top - th, right, top, 0.22, 0.24, 0.30)
  i = push_quad(buf, i, right - th, bottom, right, top, 0.22, 0.24, 0.30)
  i = push_quad(buf, i, left, bottom, right, bottom + th, 0.22, 0.24, 0.30)
  i = push_quad(buf, i, left, bottom, left + th, top, 0.22, 0.24, 0.30)
  i = push_rotated_rect(buf, i, cx, cy, hx, hy, angle)
  ignore(i)
  buf
}

pub async fn run(background_group : @async-core.TaskGroup[Unit]) -> UInt {
  ignore(background_group)
  let gpu = @webgpu.get_gpu()
  let adapter = match gpu.request_adapter(None) {
    None => return 2U
    Some(a) => a
  }
  let device = match adapter.request_device(None) {
    Err(_) => return 3U
    Ok(d) => d
  }
  let queue = device.queue()
  let format = gpu.get_preferred_canvas_format()
  let surface = @surface.Surface::surface({ height: None, width: None })
  let ctx = @sw.Context::context(surface)
  ctx.configure(
    {
      device,
      format,
      usage: Some(@webgpu.GpuTextureUsage::default().set(RENDER_ATTACHMENT)),
      view_formats: None,
      color_space: None,
      tone_mapping: None,
      alpha_mode: None,
    },
  )
  let shader = device.create_shader_module(
    { code: SHADER, compilation_hints: None, label: Some("border-2d") },
  )
  let pipeline = device.create_render_pipeline(
    {
      vertex: {
        buffers: Some(
          [
            Some(
              {
                array_stride: 24UL,
                step_mode: Some(@webgpu.GpuVertexStepMode::VERTEX),
                attributes: [
                  {
                    format: @webgpu.GpuVertexFormat::FLOAT32X3,
                    offset: 0UL,
                    shader_location: 0U,
                  },
                  {
                    format: @webgpu.GpuVertexFormat::FLOAT32X3,
                    offset: 12UL,
                    shader_location: 1U,
                  },
                ],
              },
            ),
          ],
        ),
        module_: shader,
        entry_point: Some("vs_main"),
        constants: None,
      },
      primitive: Some(
        {
          topology: Some(@webgpu.GpuPrimitiveTopology::TRIANGLE_LIST),
          strip_index_format: None,
          front_face: Some(@webgpu.GpuFrontFace::CCW),
          cull_mode: Some(@webgpu.GpuCullMode::NONE),
          unclipped_depth: None,
        },
      ),
      depth_stencil: None,
      multisample: None,
      fragment: Some(
        {
          targets: [
            Some(
              { format, blend: None, write_mask: None },
            ),
          ],
          module_: shader,
          entry_point: Some("fs_main"),
          constants: None,
        },
      ),
      layout: @webgpu.GpuLayoutMode::Auto,
      label: Some("border-2d-pipeline"),
    },
  )
  let vertex_buf = device.create_buffer(
    {
      size: SCENE_VERTEX_BYTES,
      usage: @webgpu.GpuBufferUsage::default().set(VERTEX).set(COPY_DST),
      mapped_at_creation: None,
      label: Some("border-2d-vertex"),
    },
  )
  let frames = surface.on_frame()
  // Perimeter in NDC is 7.2; 1.5 units/s ≈ 4.8 s/lap. Slow enough to track
  // by eye; a 2-frame rewind is still a few pixels on the short edges.
  let speed = 1.5
  let left = -0.90
  let right = 0.90
  let bottom = -0.90
  let top = 0.90
  let spin = 1.5
  let presented = for presented = 0U, dist = 0.0, angle = 0.0, last_ns = 0UL {
    match frames.read(1) {
      None => break presented
      Some(chunk) => {
        if chunk.length() == 0 {
          continue presented, dist, angle, last_ns
        }
        let now_ns = monotonic_now_ns()
        let dt = frame_delta_sec(last_ns, now_ns)
        let next_dist = dist + speed * dt
        let next_angle = fold_pi(angle + spin * dt)
        let color_tex = ctx.get_current_texture()
        // NativeGpu `[method]gpu-texture.width/height` is stubbed to 1.
        // Elongated two-tone rect ≈ 100×60 px on 1260×2800; spin is the hitch cue.
        let hx = 0.085
        let hy = 0.022
        let (cx, cy) = perimeter_xy(next_dist, left, right, bottom, top)
        ignore(
          queue.write_buffer_with_copy(
            vertex_buf,
            0UL,
            scene_vertices(cx, cy, hx, hy, next_angle),
            Some(0UL),
            Some(SCENE_VERTEX_BYTES),
          ),
        )
        let color_view = color_tex.create_view(None)
        let encoder = device.create_command_encoder(None)
        let pass = encoder.begin_render_pass(
          {
            color_attachments: [
              Some(
                {
                  view: color_view,
                  depth_slice: None,
                  resolve_target: None,
                  clear_value: Some({ r: 0.05, g: 0.06, b: 0.09, a: 1.0 }),
                  load_op: @webgpu.GpuLoadOp::CLEAR,
                  store_op: @webgpu.GpuStoreOp::STORE,
                },
              ),
            ],
            depth_stencil_attachment: None,
            occlusion_query_set: None,
            timestamp_writes: None,
            max_draw_count: None,
            label: None,
          },
        )
        pass.set_pipeline(pipeline)
        pass.set_vertex_buffer(0U, Some(vertex_buf), Some(0UL), Some(SCENE_VERTEX_BYTES))
        pass.draw(SCENE_VERTEX_COUNT, Some(1U), Some(0U), Some(0U))
        pass.end()
        let cmd = encoder.finish(None)
        queue.submit([cmd])
        ctx.present()
        pass.drop()
        cmd.drop()
        encoder.drop()
        color_view.drop()
        color_tex.drop()
        continue presented + 1U, next_dist, next_angle, now_ns
      }
    }
  }
  frames.drop()
  presented
}
