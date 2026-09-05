/// Texture / copy / write-texture / map. Cube never reached this pin.
/// Return: 1 = mapped bytes match; 2 = no adapter/device; 10+ = step failed.

pub async fn run(background_group : @async-core.TaskGroup[Unit]) -> UInt {
  ignore(background_group)
  let device = match boot_device() {
    None => return 2U
    Some(d) => d
  }
  let queue = device.queue()
  let texture = device.create_texture(
    {
      size: { width: 1U, height: Some(1U), depth_or_array_layers: Some(1U) },
      mip_level_count: None,
      sample_count: None,
      dimension: None,
      format: @webgpu.GpuTextureFormat::RGBA8UNORM,
      usage: @webgpu.GpuTextureUsage::default().set(COPY_SRC).set(COPY_DST),
      view_formats: None,
      texture_binding_view_dimension: None,
      label: Some("texel"),
    },
  )
  let pixels = FixedArray::make(4, b'\x00')
  pixels[0] = b'\x11'
  pixels[1] = b'\x22'
  pixels[2] = b'\x33'
  pixels[3] = b'\x44'
  queue.write_texture_with_copy(
    { texture, mip_level: None, origin: None, aspect: None },
    pixels,
    { offset: None, bytes_per_row: None, rows_per_image: None },
    { width: 1U, height: Some(1U), depth_or_array_layers: Some(1U) },
  )
  let buf = device.create_buffer(
    {
      size: 256UL,
      usage: @webgpu.GpuBufferUsage::default().set(COPY_DST).set(MAP_READ),
      mapped_at_creation: None,
      label: Some("readback"),
    },
  )
  let encoder = device.create_command_encoder(None)
  encoder.copy_texture_to_buffer(
    { texture, mip_level: None, origin: None, aspect: None },
    { buffer: buf, offset: None, bytes_per_row: Some(256U), rows_per_image: None },
    { width: 1U, height: Some(1U), depth_or_array_layers: Some(1U) },
  )
  let cmd = encoder.finish(None)
  queue.submit([cmd])
  cmd.drop()
  encoder.drop()
  match buf.map_async(@webgpu.GpuMapMode::default().set(READ), None, None) {
    Err(_) => return 11U
    Ok(_) => ()
  }
  let mapped = match buf.get_mapped_range_get_with_copy(None, Some(4UL)) {
    Err(_) => return 12U
    Ok(b) => b
  }
  if mapped.length() < 4 || mapped[0] != b'\x11' || mapped[1] != b'\x22' ||
    mapped[2] != b'\x33' || mapped[3] != b'\x44' {
    ignore(buf.unmap())
    return 13U
  }
  ignore(buf.unmap())
  ignore(stdout_line("TEXTURE_OK\n"))
  1U
}
