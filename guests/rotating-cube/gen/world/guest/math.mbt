/// Column-major 4×4 helpers for the rotating-cube MVP uniform.

fn f32_bytes(buf : FixedArray[Byte], offset : Int, value : Float) -> Unit {
  let bits = value.reinterpret_as_uint()
  buf[offset] = (bits & 255U).to_byte()
  buf[offset + 1] = ((bits >> 8) & 255U).to_byte()
  buf[offset + 2] = ((bits >> 16) & 255U).to_byte()
  buf[offset + 3] = ((bits >> 24) & 255U).to_byte()
}

fn u16_bytes(buf : FixedArray[Byte], offset : Int, value : UInt) -> Unit {
  buf[offset] = (value & 255U).to_byte()
  buf[offset + 1] = ((value >> 8) & 255U).to_byte()
}

fn mat4_identity() -> FixedArray[Double] {
  let m = FixedArray::make(16, 0.0)
  m[0] = 1.0
  m[5] = 1.0
  m[10] = 1.0
  m[15] = 1.0
  m
}

fn mat4_mul(a : FixedArray[Double], b : FixedArray[Double]) -> FixedArray[Double] {
  let o = FixedArray::make(16, 0.0)
  for col = 0; col < 4; col = col + 1 {
    for row = 0; row < 4; row = row + 1 {
      let mut s = 0.0
      for k = 0; k < 4; k = k + 1 {
        s = s + a[row + k * 4] * b[k + col * 4]
      }
      o[row + col * 4] = s
    }
  }
  o
}

fn mat4_write(buf : FixedArray[Byte], m : FixedArray[Double]) -> Unit {
  for i = 0; i < 16; i = i + 1 {
    f32_bytes(buf, i * 4, Float::from_double(m[i]))
  }
}

fn wrap_pi(x : Double) -> Double {
  let pi = 3.141592653589793
  let two_pi = 6.283185307179586
  let mut y = x
  while y > pi {
    y = y - two_pi
  }
  while y < -pi {
    y = y + two_pi
  }
  y
}

fn sin_d(x : Double) -> Double {
  let y = wrap_pi(x)
  let y2 = y * y
  y * (1.0 + y2 * (-1.0 / 6.0 + y2 * (1.0 / 120.0 + y2 * (-1.0 / 5040.0))))
}

fn cos_d(x : Double) -> Double {
  sin_d(x + 1.5707963267948966)
}

fn mat4_rotate_x(radians : Double) -> FixedArray[Double] {
  let c = cos_d(radians)
  let s = sin_d(radians)
  let m = mat4_identity()
  m[5] = c
  m[6] = s
  m[9] = -s
  m[10] = c
  m
}

fn mat4_rotate_y(radians : Double) -> FixedArray[Double] {
  let c = cos_d(radians)
  let s = sin_d(radians)
  let m = mat4_identity()
  m[0] = c
  m[2] = -s
  m[8] = s
  m[10] = c
  m
}

fn tan_half(fov_y : Double) -> Double {
  let half = fov_y * 0.5
  let s = sin_d(half)
  if s == 0.0 {
    1.0
  } else {
    sin_d(half) / cos_d(half)
  }
}

fn mat4_perspective(fov_y : Double, aspect : Double, near : Double, far : Double) -> FixedArray[Double] {
  let f = 1.0 / tan_half(fov_y)
  let m = FixedArray::make(16, 0.0)
  if aspect != 0.0 {
    m[0] = f / aspect
  }
  m[5] = f
  m[10] = (far + near) / (near - far)
  m[11] = -1.0
  m[14] = 2.0 * far * near / (near - far)
  m
}

fn vec3_norm(x : Double, y : Double, z : Double) -> (Double, Double, Double) {
  let d = x * x + y * y + z * z
  let mut g = 1.0
  if d > 0.0 {
    g = d
    for i = 0; i < 8; i = i + 1 {
      g = 0.5 * (g + d / g)
    }
  }
  (x / g, y / g, z / g)
}

fn mat4_look_at(
  eye_x : Double,
  eye_y : Double,
  eye_z : Double,
  cx : Double,
  cy : Double,
  cz : Double,
  up_x : Double,
  up_y : Double,
  up_z : Double,
) -> FixedArray[Double] {
  let (fx, fy, fz) = vec3_norm(cx - eye_x, cy - eye_y, cz - eye_z)
  let (sx, sy, sz) = vec3_norm(fy * up_z - fz * up_y, fz * up_x - fx * up_z, fx * up_y - fy * up_x)
  let ux = sy * fz - sz * fy
  let uy = sz * fx - sx * fz
  let uz = sx * fy - sy * fx
  let m = mat4_identity()
  m[0] = sx
  m[4] = sy
  m[8] = sz
  m[1] = ux
  m[5] = uy
  m[9] = uz
  m[2] = -fx
  m[6] = -fy
  m[10] = -fz
  m[12] = -(sx * eye_x + sy * eye_y + sz * eye_z)
  m[13] = -(ux * eye_x + uy * eye_y + uz * eye_z)
  m[14] = fx * eye_x + fy * eye_y + fz * eye_z
  m
}

fn mvp_bytes(angle : Double, aspect : Double) -> FixedArray[Byte] {
  let model = mat4_mul(mat4_rotate_y(angle), mat4_rotate_x(angle * 0.35))
  let view = mat4_look_at(0.0, 1.35, 3.6, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0)
  let proj = mat4_perspective(0.7853981633974483, aspect, 0.1, 100.0)
  let mvp = mat4_mul(proj, mat4_mul(view, model))
  let buf = FixedArray::make(256, b'\x00')
  mat4_write(buf, mvp)
  buf
}
