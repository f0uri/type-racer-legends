import 'dart:math';
import 'dart:typed_data';

/// Procedurally synthesised sound effects and music (original, royalty-free, no audio assets needed).
class Synth {
  static const sampleRate = 22050;

  static Uint8List wav(Float32List s) {
    final n = s.length;
    final b = ByteData(44 + n * 2);
    void str(int o, String v) {
      for (var i = 0; i < v.length; i++) {
        b.setUint8(o + i, v.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    b.setUint32(4, 36 + n * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little);
    b.setUint16(22, 1, Endian.little);
    b.setUint32(24, sampleRate, Endian.little);
    b.setUint32(28, sampleRate * 2, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    str(36, 'data');
    b.setUint32(40, n * 2, Endian.little);
    for (var i = 0; i < n; i++) {
      b.setInt16(44 + i * 2, (s[i].clamp(-1.0, 1.0) * 32000).round(), Endian.little);
    }
    return b.buffer.asUint8List();
  }

  static Float32List _buf(double seconds) => Float32List((seconds * sampleRate).round());

  static double _osc(String wave, double phase) {
    final p = phase - phase.floorToDouble();
    switch (wave) {
      case 'square':
        return p < 0.5 ? 0.6 : -0.6;
      case 'saw':
        return (p * 2 - 1) * 0.7;
      case 'tri':
        return (p < 0.5 ? p * 4 - 1 : 3 - p * 4) * 0.8;
      default:
        return sin(2 * pi * p);
    }
  }

  /// A sequence of tones [[freq, ms], ...] with a short envelope each.
  static Uint8List tones(List<List<num>> seq, {String wave = 'sine', double vol = 0.5}) {
    final total = seq.fold<double>(0, (a, e) => a + e[1] / 1000);
    final out = _buf(total + 0.05);
    var o = 0;
    for (final e in seq) {
      final f = e[0].toDouble();
      final n = (e[1] / 1000 * sampleRate).round();
      var ph = 0.0;
      for (var i = 0; i < n && o + i < out.length; i++) {
        final t = i / n;
        final env = min(1.0, i / 120) * (1 - t) * (1 - t * 0.3);
        ph += f / sampleRate;
        out[o + i] += _osc(wave, ph) * env * vol;
      }
      o += n;
    }
    return wav(out);
  }

  static Uint8List click() {
    final out = _buf(0.05);
    final r = Random(1);
    for (var i = 0; i < out.length; i++) {
      final t = i / out.length;
      out[i] = (sin(2 * pi * 1900 * i / sampleRate) * 0.35 + (r.nextDouble() - 0.5) * 0.25) * pow(1 - t, 3);
    }
    return wav(out);
  }

  static Uint8List wrong() {
    final out = _buf(0.16);
    var ph = 0.0;
    for (var i = 0; i < out.length; i++) {
      final t = i / out.length;
      ph += (170 - 60 * t) / sampleRate;
      out[i] = _osc('square', ph) * 0.4 * (1 - t);
    }
    return wav(out);
  }

  static Uint8List whoosh({double seconds = 0.9, double from = 180, double to = 1100}) {
    final out = _buf(seconds);
    final r = Random(4);
    var ph = 0.0, lp = 0.0;
    for (var i = 0; i < out.length; i++) {
      final t = i / out.length;
      final f = from + (to - from) * t * t;
      ph += f / sampleRate;
      lp += ((r.nextDouble() - 0.5) - lp) * (0.05 + 0.4 * t);
      final env = sin(pi * t) * 0.9;
      out[i] = (_osc('saw', ph) * 0.25 + lp * 1.3) * env * 0.7;
    }
    return wav(out);
  }

  static Uint8List thump() {
    final out = _buf(0.32);
    final r = Random(9);
    var ph = 0.0, lp = 0.0;
    for (var i = 0; i < out.length; i++) {
      final t = i / out.length;
      ph += (90 - 50 * t) / sampleRate;
      lp += ((r.nextDouble() - 0.5) - lp) * 0.15;
      out[i] = (sin(2 * pi * ph) * 0.8 + lp * 0.6) * pow(1 - t, 2.2);
    }
    return wav(out);
  }

  /// Seamless engine loop: harmonics of a base frequency over an integer number of cycles.
  static Uint8List engineLoop() {
    const base = 62.0; // Hz
    const cycles = 31; // 0.5 s
    final n = (cycles / base * sampleRate).round();
    final out = Float32List(n);
    for (var i = 0; i < n; i++) {
      final t = i / n;
      final ph = t * cycles;
      final lfo = 0.85 + 0.15 * sin(2 * pi * t * 8);
      var v = 0.0;
      for (var h = 1; h <= 7; h++) {
        v += sin(2 * pi * ph * h) / (h * 0.9) * (h.isEven ? 0.7 : 1.0);
      }
      out[i] = (v * 0.18 * lfo).clamp(-0.9, 0.9);
    }
    return wav(out);
  }

  /// 16-second upbeat synthwave loop (Am - F - C - G) with kick and arpeggio.
  static Uint8List music() {
    const bpm = 112.0;
    const beat = 60 / bpm;
    final total = beat * 32;
    final out = _buf(total);
    final chords = [
      [220.0, 261.63, 329.63],
      [174.61, 220.0, 261.63],
      [261.63, 329.63, 392.0],
      [196.0, 246.94, 293.66],
    ];
    final bass = [55.0, 43.65, 65.41, 49.0];
    for (var i = 0; i < out.length; i++) {
      final t = i / sampleRate;
      final bt = t / beat;
      final bar = (bt / 8).floor() % 4;
      final inBeat = bt - bt.floorToDouble();
      var v = 0.0;
      // kick on every beat
      if (inBeat < 0.25) {
        final k = inBeat * beat;
        v += sin(2 * pi * (110 * exp(-k * 18) + 40) * k) * 0.45 * (1 - inBeat * 4);
      }
      // bass (off-beat eighths)
      final eighth = (bt * 2).floor();
      final ep = bt * 2 - eighth;
      if (eighth.isOdd) v += _osc('saw', t * bass[bar]) * 0.18 * (1 - ep);
      // arpeggio sixteenths
      final sx = (bt * 4).floor();
      final sp = bt * 4 - sx;
      final note = chords[bar][sx % 3] * (sx % 6 < 3 ? 2 : 1);
      v += _osc('tri', t * note) * 0.14 * pow(1 - sp, 1.5);
      // soft pad
      for (final f in chords[bar]) {
        v += sin(2 * pi * f * t) * 0.03;
      }
      // hi-hat
      if (eighth.isOdd && ep < 0.15) v += (((i * 7919) % 1000) / 1000 - 0.5) * 0.08;
      out[i] = v * 0.8;
    }
    // fade ends so the loop is click-free
    for (var i = 0; i < 400; i++) {
      final f = i / 400;
      out[i] *= f;
      out[out.length - 1 - i] *= f;
    }
    return wav(out);
  }

  static Uint8List fanfare() => tones([
        [523.25, 120],
        [659.25, 120],
        [783.99, 120],
        [1046.5, 380],
        [783.99, 100],
        [1046.5, 500],
      ], wave: 'tri', vol: 0.55);

  static Uint8List ding() => tones([[988, 90], [1319, 260]], wave: 'sine', vol: 0.5);
  static Uint8List beep() => tones([[440, 140]], wave: 'sine', vol: 0.5);
  static Uint8List go() => tones([[880, 420]], wave: 'sine', vol: 0.6);
  static Uint8List coin() => tones([[1175, 60], [1568, 220]], wave: 'square', vol: 0.25);
  static Uint8List power() => tones([[392, 70], [523, 70], [659, 70], [880, 200]], wave: 'tri', vol: 0.5);
  static Uint8List pit() => tones([[300, 50], [0, 40], [300, 50], [0, 40], [600, 120]], wave: 'square', vol: 0.3);
  static Uint8List chest() => tones([[392, 100], [494, 100], [587, 100], [784, 100], [988, 100], [1175, 400]], wave: 'tri', vol: 0.5);
  static Uint8List levelUp() => tones([[523, 110], [659, 110], [784, 110], [1046, 110], [1318, 420]], wave: 'sine', vol: 0.55);
  static Uint8List combo(int tier) {
    final base = 523.25 * pow(2, (tier - 1) / 12 * 2);
    return tones([[base, 70], [base * 1.5, 160]], wave: 'sine', vol: 0.45);
  }
}
