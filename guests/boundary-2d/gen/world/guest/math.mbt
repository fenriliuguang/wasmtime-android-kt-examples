/// Packed f32 for the 2D NDC vertex buffer. `sincos_d` is guest-owned
/// (MoonBit has no libc sin/cos). Notes: docs/moonbit-guest-math.md.
///
/// `fold_pi` is safe here: one spin angle, so R(θ+2π)=R(θ). Do not fold a
/// shared Euler clock used at different rates on X/Y/Z.

fn f32_bytes(buf : FixedArray[Byte], offset : Int, value : Float) -> Unit {
  let bits = value.reinterpret_as_uint()
  buf[offset] = (bits & 255U).to_byte()
  buf[offset + 1] = ((bits >> 8) & 255U).to_byte()
  buf[offset + 2] = ((bits >> 16) & 255U).to_byte()
  buf[offset + 3] = ((bits >> 24) & 255U).to_byte()
}

/// Fold into (-π, π] so each frame's argument stays well-conditioned.
fn fold_pi(x : Double) -> Double {
  let pi = 3.141592653589793
  let two_pi = 6.283185307179586
  if x > pi {
    x - two_pi
  } else if x < -pi {
    x + two_pi
  } else {
    x
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
  let z = x * x
  let c1 = 0.0416666666666666
  let c2 = -0.001388888888887411
  let c3 = 0.00002480158728947673
  let c4 = -0.0000002755731435139066
  let c5 = 0.000000002087572321298175
  let c6 = -0.00000000001135964755778819
  1.0 - 0.5 * z + z * z * (c1 + z * (c2 + z * (c3 + z * (c4 + z * (c5 + z * c6)))))
}

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
