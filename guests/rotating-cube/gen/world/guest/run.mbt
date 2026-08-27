/// Rotating colorful cube: `wasi:webgpu` + `wasi-gfx` `on-frame` loop.

const SHADER : String =
  #|struct Uniforms { mvp : mat4x4<f32> }
  #|@group(0) @binding(0) var<uniform> u : Uniforms;
  #|struct VSOut {
  #|  @builtin(position) pos : vec4<f32>,
  #|  @location(0) color : vec3<f32>,
  #|}
  #|@vertex
  #|fn vs_main(@location(0) position : vec3<f32>, @location(1) color : vec3<f32>) -> VSOut {
  #|  var out : VSOut;
  #|  out.pos = u.mvp * vec4<f32>(position, 1.0);
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
  z : Float,
  r : Float,
  g : Float,
  b : Float,
) -> Int {
  f32_bytes(buf, i, x)
  f32_bytes(buf, i + 4, y)
  f32_bytes(buf, i + 8, z)
  f32_bytes(buf, i + 12, r)
  f32_bytes(buf, i + 16, g)
  f32_bytes(buf, i + 20, b)
  i + 24
}

fn cube_vertices() -> FixedArray[Byte] {
  let buf = FixedArray::make(36 * 24, b'\x00')
  let mut i = 0
  fn face(
    buf : FixedArray[Byte],
    i : Int,
    ax : Double, ay : Double, az : Double,
    bx : Double, by : Double, bz : Double,
    cx : Double, cy : Double, cz : Double,
    dx : Double, dy : Double, dz : Double,
    r : Double, g : Double, b : Double,
  ) -> Int {
    // two triangles: a-b-c, a-c-d
    let mut o = i
    o = push_vertex(buf, o, ff(ax), ff(ay), ff(az), ff(r), ff(g), ff(b))
    o = push_vertex(buf, o, ff(bx), ff(by), ff(bz), ff(r), ff(g), ff(b))
    o = push_vertex(buf, o, ff(cx), ff(cy), ff(cz), ff(r), ff(g), ff(b))
    o = push_vertex(buf, o, ff(ax), ff(ay), ff(az), ff(r), ff(g), ff(b))
    o = push_vertex(buf, o, ff(cx), ff(cy), ff(cz), ff(r), ff(g), ff(b))
    o = push_vertex(buf, o, ff(dx), ff(dy), ff(dz), ff(r), ff(g), ff(b))
    o
  }
  // +Z cyan
  i = face(buf, i, -1.0, -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, 1.0, 1.0, -1.0, 1.0, 1.0, 0.15, 0.85, 0.95)
  // +X red
  i = face(buf, i, 1.0, -1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, 1.0, 0.95, 0.25, 0.2)
  // -Z magenta
  i = face(buf, i, 1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, 1.0, -1.0, 1.0, 1.0, -1.0, 0.9, 0.2, 0.75)
  // -X green
  i = face(buf, i, -1.0, -1.0, -1.0, -1.0, -1.0, 1.0, -1.0, 1.0, 1.0, -1.0, 1.0, -1.0, 0.2, 0.8, 0.35)
  // +Y blue
  i = face(buf, i, -1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, -1.0, -1.0, 1.0, -1.0, 0.25, 0.4, 0.95)
  // -Y yellow
  i = face(buf, i, -1.0, -1.0, -1.0, 1.0, -1.0, -1.0, 1.0, -1.0, 1.0, -1.0, -1.0, 1.0, 0.95, 0.85, 0.2)
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
    { code: SHADER, compilation_hints: None, label: Some("cube") },
  )
  let bgl = device.create_bind_group_layout(
    {
      entries: [
        {
          binding: 0U,
          visibility: @webgpu.GpuShaderStage::default().set(VERTEX),
          buffer: Some(
            {
              type_: Some(@webgpu.GpuBufferBindingType::UNIFORM),
              has_dynamic_offset: None,
              min_binding_size: Some(64UL),
            },
          ),
          sampler: None,
          texture: None,
          storage_texture: None,
        },
      ],
      label: None,
    },
  )
  let layout = device.create_pipeline_layout(
    {
      bind_group_layouts: [Some(bgl)],
      immediate_size: None,
      label: None,
    },
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
          cull_mode: Some(@webgpu.GpuCullMode::BACK),
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
      layout: @webgpu.GpuLayoutMode::Specific(layout),
      label: Some("cube-pipeline"),
    },
  )
  let vertex_buf = device.create_buffer(
    {
      size: 864UL,
      usage: @webgpu.GpuBufferUsage::default().set(VERTEX).set(COPY_DST),
      mapped_at_creation: None,
      label: Some("cube-vertex"),
    },
  )
  let uniform_buf = device.create_buffer(
    {
      size: 256UL,
      usage: @webgpu.GpuBufferUsage::default().set(UNIFORM).set(COPY_DST),
      mapped_at_creation: None,
      label: Some("cube-uniform"),
    },
  )
  ignore(queue.write_buffer_with_copy(vertex_buf, 0UL, cube_vertices(), Some(0UL), Some(864UL)))
  let bind_group = device.create_bind_group(
    {
      layout: bgl,
      entries: [
        {
          binding: 0U,
          resource: @webgpu.GpuBindingResource::GpuBufferBinding(
            { buffer: uniform_buf, offset: None, size: Some(256UL) },
          ),
        },
      ],
      label: None,
    },
  )
  let frames = surface.on_frame()
  let mut aspect = 1.0
  // ~0.025 rad/tick at 60 Hz. Delta from clocks.now, not per-event (rAF model).
  let rad_per_sec = 0.025 * 60.0
  let presented = for presented = 0U, angle = 0.0, last_ns = 0UL {
    match frames.read(1) {
      None => break presented
      Some(chunk) => {
        if chunk.length() == 0 {
          continue presented, angle, last_ns
        }
        let now_ns = monotonic_now_ns()
        let next_angle = angle + rad_per_sec * frame_delta_sec(last_ns, now_ns)
        let color_tex = ctx.get_current_texture()
        let tw = color_tex.width()
        let th = color_tex.height()
        if th != 0U {
          aspect = tw.reinterpret_as_int().to_double() / th.reinterpret_as_int().to_double()
        }
        ignore(
          queue.write_buffer_with_copy(
            uniform_buf,
            0UL,
            mvp_bytes(next_angle, aspect),
            Some(0UL),
            Some(64UL),
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
                  clear_value: Some({ r: 0.06, g: 0.07, b: 0.12, a: 1.0 }),
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
        ignore(pass.set_bind_group(0U, Some(bind_group), None, None, None))
        pass.set_vertex_buffer(0U, Some(vertex_buf), Some(0UL), Some(864UL))
        pass.draw(36U, Some(1U), Some(0U), Some(0U))
        pass.end()
        let cmd = encoder.finish(None)
        queue.submit([cmd])
        ctx.present()
        // Per-frame WIT owns. Without drop, Wasmtime's resource table grows
        // until nativeCallRunConcurrent SIGSEGV. Host recycles Dawn objects
        // on a delayed ring — drop here only ends the CM own.
        pass.drop()
        cmd.drop()
        encoder.drop()
        color_view.drop()
        color_tex.drop()
        continue presented + 1U, next_angle, now_ns
      }
    }
  }
  frames.drop()
  presented
}
