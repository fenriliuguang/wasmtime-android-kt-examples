/// Pointer / keyboard + request-set-size. Host auto-posts one pointer-down.
/// Return: 1 = resize + pointer-down seen; 2+ = which step failed.

pub async fn run(background_group : @async-core.TaskGroup[Unit]) -> UInt {
  ignore(background_group)
  let surface = @surface.Surface::surface({ height: None, width: None })
  let h = surface.height()
  let w = surface.width()
  if h == 0U || w == 0U {
    return 2U
  }
  let resize = surface.on_resize()
  surface.request_set_size(Some(96U), Some(80U))
  match resize.read(1) {
    None => return 3U
    Some(chunk) => {
      if chunk.length() == 0 {
        return 4U
      }
    }
  }
  resize.drop()
  let down = surface.on_pointer_down()
  match down.read(1) {
    None => return 5U
    Some(chunk) => {
      if chunk.length() == 0 {
        return 6U
      }
    }
  }
  down.drop()
  // Remaining pin streams: open + drop (cancel). Keyboard is posted by host.
  surface.on_pointer_up().drop()
  surface.on_pointer_move().drop()
  surface.on_key_up().drop()
  surface.on_key_down().drop()
  ignore(stdout_line("POINTER_OK\n"))
  1U
}
