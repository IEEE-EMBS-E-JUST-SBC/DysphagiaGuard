import 'dart:math' as math;

/// Computes the one-sided magnitude spectrum of a real-valued signal,
/// matching numpy's `np.fft.rfft` bin-for-bin.
///
/// IMPORTANT: this uses a direct O(N²) DFT rather than a radix-2 FFT.
/// The training pipeline (Python/numpy) calls `np.fft.rfft` directly on
/// the raw N=300 sample window — it does NOT zero-pad to a power of two.
/// An earlier version of this file used a padded radix-2 FFT (300→512),
/// which was verified against numpy to be internally correct as an FFT,
/// but produced spectral centroid/flatness values ~10% different from
/// training because padding changes the frequency bin spacing. A direct
/// DFT avoids that mismatch entirely and exactly reproduces numpy's
/// rfft output (verified to float precision). At N=300, computed once
/// per 3-second window, the O(N²) cost (~90k multiply-adds) is trivial
/// on a phone and not a real-time bottleneck.
class SimpleFFT {
  /// Computes the one-sided magnitude spectrum and matching frequency
  /// bins for a real-valued signal `x`, sampled at `fs` Hz. Output has
  /// `x.length ~/ 2 + 1` bins, exactly matching `np.fft.rfftfreq`.
  static (List<double> freqs, List<double> mags) magnitudeSpectrum(
    List<double> x,
    double fs,
  ) {
    final n = x.length;
    final half = n ~/ 2 + 1;
    final freqs = List<double>.generate(half, (k) => k * fs / n);
    final mags = List<double>.filled(half, 0.0);

    for (var k = 0; k < half; k++) {
      var re = 0.0;
      var im = 0.0;
      final angleStep = -2 * math.pi * k / n;
      for (var t = 0; t < n; t++) {
        final angle = angleStep * t;
        re += x[t] * math.cos(angle);
        im += x[t] * math.sin(angle);
      }
      mags[k] = math.sqrt(re * re + im * im);
    }
    return (freqs, mags);
  }

  // ---------------------------------------------------------------------
  // The radix-2 FFT below is kept ONLY for reference/potential future use
  // on power-of-two window sizes. It is NOT used by magnitudeSpectrum
  // above and is not wired into the feature extractor. Do not use it for
  // this model's feature extraction — see the class doc comment.
  // ---------------------------------------------------------------------

  /// In-place iterative Cooley-Tukey FFT. `re`/`im` length must be a
  /// power of two.
  static void _fftInPlace(List<double> re, List<double> im) {
    final n = re.length;
    if (n <= 1) return;

    // Bit-reversal permutation
    var j = 0;
    for (var i = 1; i < n; i++) {
      var bit = n >> 1;
      while (j & bit != 0) {
        j ^= bit;
        bit >>= 1;
      }
      j ^= bit;
      if (i < j) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }

    // Iterative Cooley-Tukey
    for (var len = 2; len <= n; len <<= 1) {
      final ang = -2 * math.pi / len;
      final wRe = math.cos(ang);
      final wIm = math.sin(ang);
      for (var i = 0; i < n; i += len) {
        var curWRe = 1.0;
        var curWIm = 0.0;
        for (var k = 0; k < len ~/ 2; k++) {
          final uRe = re[i + k];
          final uIm = im[i + k];
          final vRe = re[i + k + len ~/ 2] * curWRe - im[i + k + len ~/ 2] * curWIm;
          final vIm = re[i + k + len ~/ 2] * curWIm + im[i + k + len ~/ 2] * curWRe;

          re[i + k] = uRe + vRe;
          im[i + k] = uIm + vIm;
          re[i + k + len ~/ 2] = uRe - vRe;
          im[i + k + len ~/ 2] = uIm - vIm;

          final nextWRe = curWRe * wRe - curWIm * wIm;
          final nextWIm = curWRe * wIm + curWIm * wRe;
          curWRe = nextWRe;
          curWIm = nextWIm;
        }
      }
    }
  }
}
