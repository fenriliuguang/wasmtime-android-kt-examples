/// Compute smoke (no present): adapter → device → queue → compute pass → submit.
/// Return: 1 = dispatched; 2 = no adapter; 3 = no device.

const COMPUTE_SHADER : String =
  #|@group(0) @binding(0) var<storage, read_write> data : array<u32>;
  #|@compute @workgroup_size(1)
  #|fn main() {
  #|  data[0] = 42u;
  #|}

pub async fn run(background_group : @async-core.TaskGroup[Unit]) -> UInt {
  ignore(background_group)
  let device = match boot_device() {
    None => return 2U
    Some(d) => d
  }
  let queue = device.queue()
  let shader = device.create_shader_module(
    { code: COMPUTE_SHADER, compilation_hints: None, label: Some("compute") },
  )
  let bgl = device.create_bind_group_layout(
    {
      entries: [
        {
          binding: 0U,
          visibility: @webgpu.GpuShaderStage::default().set(COMPUTE),
          buffer: Some(
            {
              type_: Some(@webgpu.GpuBufferBindingType::STORAGE),
              has_dynamic_offset: None,
              min_binding_size: Some(4UL),
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
  let pipeline = device.create_compute_pipeline(
    {
      compute: { module_: shader, entry_point: Some("main"), constants: None },
      layout: @webgpu.GpuLayoutMode::Specific(layout),
      label: Some("compute-pipeline"),
    },
  )
  let storage = device.create_buffer(
    {
      size: 4UL,
      usage: @webgpu.GpuBufferUsage::default().set(STORAGE).set(COPY_SRC).set(COPY_DST),
      mapped_at_creation: None,
      label: Some("storage"),
    },
  )
  let zeros = FixedArray::make(4, b'\x00')
  ignore(queue.write_buffer_with_copy(storage, 0UL, zeros, Some(0UL), Some(4UL)))
  let bind_group = device.create_bind_group(
    {
      layout: bgl,
      entries: [
        {
          binding: 0U,
          resource: @webgpu.GpuBindingResource::GpuBufferBinding(
            { buffer: storage, offset: None, size: Some(4UL) },
          ),
        },
      ],
      label: None,
    },
  )
  let encoder = device.create_command_encoder(None)
  let pass = encoder.begin_compute_pass(None)
  pass.set_pipeline(pipeline)
  ignore(pass.set_bind_group(0U, Some(bind_group), None, None, None))
  pass.dispatch_workgroups(1U, None, None)
  pass.end()
  let cmd = encoder.finish(None)
  queue.submit([cmd])
  pass.drop()
  cmd.drop()
  encoder.drop()
  ignore(stdout_line("COMPUTE_OK\n"))
  1U
}
