import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'sfx_synth.dart';

enum Sfx { click, wrong, whoosh, thump, beep, go, fanfare, ding, coin, power, pit, chest, levelUp, combo2, combo3, combo4, combo5, combo6, horn }

/// Plays procedurally generated sounds. All failures are swallowed so audio never crashes the game
/// (e.g. on devices without audio output or when running in tests).
class AudioService {
  AudioService();
  final Map<Sfx, Uint8List> _cache = {};
  final List<AudioPlayer> _pool = [];
  int _next = 0;
  AudioPlayer? _engine, _music;
  Uint8List? _engineBytes, _musicBytes;
  Uint8List? _horn;
  bool sfxOn = true, musicOn = true;
  double sfxVol = 0.8, musicVol = 0.5;
  bool _engineRunning = false, _musicRunning = false, disposed = false;
  bool available = true;

  Uint8List _bytes(Sfx s) => _cache.putIfAbsent(s, () {
        switch (s) {
          case Sfx.click:
            return Synth.click();
          case Sfx.wrong:
            return Synth.wrong();
          case Sfx.whoosh:
            return Synth.whoosh();
          case Sfx.thump:
            return Synth.thump();
          case Sfx.beep:
            return Synth.beep();
          case Sfx.go:
            return Synth.go();
          case Sfx.fanfare:
            return Synth.fanfare();
          case Sfx.ding:
            return Synth.ding();
          case Sfx.coin:
            return Synth.coin();
          case Sfx.power:
            return Synth.power();
          case Sfx.pit:
            return Synth.pit();
          case Sfx.chest:
            return Synth.chest();
          case Sfx.levelUp:
            return Synth.levelUp();
          case Sfx.combo2:
            return Synth.combo(2);
          case Sfx.combo3:
            return Synth.combo(3);
          case Sfx.combo4:
            return Synth.combo(4);
          case Sfx.combo5:
            return Synth.combo(5);
          case Sfx.combo6:
            return Synth.combo(6);
          case Sfx.horn:
            return _horn ?? Synth.tones([[196, 400]], wave: 'saw', vol: 0.4);
        }
      });

  void configure({required bool sfx, required bool music, required double sfxVolume, required double musicVolume}) {
    sfxOn = sfx;
    sfxVol = sfxVolume;
    musicVol = musicVolume;
    if (music != musicOn) {
      musicOn = music;
      if (!music) {
        stopMusic();
      }
    }
    _music?.setVolume(musicVol * 0.6).catchError((_) {});
  }

  Future<void> _ensurePool() async {
    if (_pool.isNotEmpty || !available) return;
    try {
      for (var i = 0; i < 6; i++) {
        final p = AudioPlayer();
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setReleaseMode(ReleaseMode.stop);
        _pool.add(p);
      }
    } catch (e) {
      available = false;
      debugPrint('audio unavailable: $e');
    }
  }

  void setHorn(List<List<num>>? seq, String wave) {
    _horn = seq == null ? null : Synth.tones(seq, wave: wave, vol: 0.45);
    _cache.remove(Sfx.horn);
  }

  Future<void> play(Sfx s, {double vol = 1}) async {
    if (!sfxOn || disposed || !available) return;
    try {
      await _ensurePool();
      if (_pool.isEmpty) return;
      final p = _pool[_next++ % _pool.length];
      await p.setVolume((sfxVol * vol).clamp(0.0, 1.0));
      await p.play(BytesSource(_bytes(s), mimeType: 'audio/wav'));
    } catch (e) {
      debugPrint('sfx failed: $e');
    }
  }

  Future<void> startEngine() async {
    if (!sfxOn || _engineRunning || disposed || !available) return;
    try {
      _engine ??= AudioPlayer();
      _engineBytes ??= Synth.engineLoop();
      await _engine!.setReleaseMode(ReleaseMode.loop);
      await _engine!.setVolume(sfxVol * 0.22);
      await _engine!.play(BytesSource(_engineBytes!, mimeType: 'audio/wav'));
      _engineRunning = true;
    } catch (e) {
      available = false;
      debugPrint('engine failed: $e');
    }
  }

  /// [speed] 0..1 maps to pitch.
  void engineSpeed(double speed) {
    if (!_engineRunning) return;
    _engine?.setPlaybackRate((0.8 + speed.clamp(0.0, 1.0) * 1.3)).catchError((_) {});
  }

  Future<void> stopEngine() async {
    if (!_engineRunning) return;
    _engineRunning = false;
    try {
      await _engine?.stop();
    } catch (_) {}
  }

  Future<void> startMusic() async {
    if (!musicOn || _musicRunning || disposed || !available) return;
    try {
      _music ??= AudioPlayer();
      _musicBytes ??= Synth.music();
      await _music!.setReleaseMode(ReleaseMode.loop);
      await _music!.setVolume(musicVol * 0.6);
      await _music!.play(BytesSource(_musicBytes!, mimeType: 'audio/wav'));
      _musicRunning = true;
    } catch (e) {
      debugPrint('music failed: $e');
    }
  }

  Future<void> stopMusic() async {
    if (!_musicRunning) return;
    _musicRunning = false;
    try {
      await _music?.stop();
    } catch (_) {}
  }

  Future<void> pauseAll() async {
    try {
      await _engine?.pause();
      await _music?.pause();
    } catch (_) {}
  }

  Future<void> resumeAll() async {
    try {
      if (_engineRunning) await _engine?.resume();
      if (_musicRunning) await _music?.resume();
    } catch (_) {}
  }

  Future<void> dispose() async {
    disposed = true;
    for (final p in _pool) {
      try {
        await p.dispose();
      } catch (_) {}
    }
    _pool.clear();
    try {
      await _engine?.dispose();
      await _music?.dispose();
    } catch (_) {}
  }
}
