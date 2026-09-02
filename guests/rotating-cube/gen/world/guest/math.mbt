/// Column-major 4×4 MVP helpers. `sincos_d` is guest-owned (MoonBit has no
/// libc sin/cos). Notes: docs/moonbit-guest-math.md.

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

fn round_nearest_int(x : Double) -> Int {
  if x >= 0.0 {
    (x + 0.5).to_int()
  } else {
    (x - 0.5).to_int()
  }
}

fn kernel_sin(x : Double) -> Double {
  // fdlibm k_sin on |x| ≤ π/4
  let z = x * x
  let s1 = -0.16666666666666632
  let s2 = 0.008333333333322489
  let s3 = -0.0001984126982985795
  let s4 = 0.000002755731370707007
  let s5 = -0.00000002505076025340686
  let s6 = 0.000000000158969099521155
  let r = z * (s1 + z * (s2 + z * (s3 + z * (s4 + z * (s5 + z * s6)))))
  x + x * r
}

fn kernel_cos(x : Double) -> Double {
  // fdlibm k_cos on |x| ≤ π/4
  let z = x * x
  let c1 = 0.0416666666666666
  let c2 = -0.001388888888887411
  let c3 = 0.00002480158728947673
  let c4 = -0.0000002755731435139066
  let c5 = 0.000000002087572321298175
  let c6 = -0.00000000001135964755778819
  1.0 - 0.5 * z + z * z * (c1 + z * (c2 + z * (c3 + z * (c4 + z * (c5 + z * c6)))))
}

/// Cody–Waite reduction to |r| ≤ π/4, then fdlibm kernels. sin/cos share
/// one (n, r) so the pair stays continuous at ±π/2 and ±π.
fn sincos_d(x : Double) -> (Double, Double) {
  let invpio2 = 0.6366197723675814
  let pio2_1 = 1.5707963267341256
  let pio2_1t = 6.077100506506192e-11
  let n = round_nearest_int(x * invpio2)
  let nf = n.to_double()
  let r = x - nf * pio2_1 - nf * pio2_1t
  let s0 = kernel_sin(r)
  let c0 = kernel_cos(r)
  let mut q = n % 4
  if q < 0 {
    q = q + 4
  }
  if q == 0 {
    (s0, c0)
  } else if q == 1 {
    (c0, -s0)
  } else if q == 2 {
    (-s0, -c0)
  } else {
    (-c0, s0)
  }
}

fn mat4_rotate_x(radians : Double) -> FixedArray[Double] {
  let (s, c) = sincos_d(radians)
  let m = mat4_identity()
  m[5] = c
  m[6] = s
  m[9] = -s
  m[10] = c
  m
}

fn mat4_rotate_y(radians : Double) -> FixedArray[Double] {
  let (s, c) = sincos_d(radians)
  let m = mat4_identity()
  m[0] = c
  m[2] = -s
  m[8] = s
  m[10] = c
  m
}

fn mat4_rotate_z(radians : Double) -> FixedArray[Double] {
  let (s, c) = sincos_d(radians)
  let m = mat4_identity()
  m[0] = c
  m[1] = s
  m[4] = -s
  m[5] = c
  m
}

fn tan_half(fov_y : Double) -> Double {
  let half = fov_y * 0.5
  let (s, c) = sincos_d(half)
  if s == 0.0 {
    1.0
  } else {
    s / c
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

/// Perspective tumble on X/Y/Z from one clock angle. Do **not** fold `angle`
/// into ±π: Ry(θ+2π)=Ry(θ), but Rx(0.35(θ+2π)) is a ~126° snap.
fn mvp_bytes(angle : Double, aspect : Double) -> FixedArray[Byte] {
  let rx = mat4_rotate_x(angle * 0.35)
  let ry = mat4_rotate_y(angle)
  let rz = mat4_rotate_z(angle * 0.21)
  let model = mat4_mul(rz, mat4_mul(ry, rx))
  let view = mat4_look_at(0.0, 1.35, 3.6, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0)
  let proj = mat4_perspective(0.7853981633974483, aspect, 0.1, 100.0)
  let mvp = mat4_mul(proj, mat4_mul(view, model))
  let buf = FixedArray::make(256, b'\x00')
  mat4_write(buf, mvp)
  buf
}
