/// Tracks one continuous play session and tells when a break should be suggested.
/// A gap of more than [gapMs] between races starts a new session.
class BreakTracker {
  BreakTracker({this.gapMs = 10 * 60 * 1000});
  final int gapMs;
  int? _sessionStart;
  int? _lastEnd;

  /// Call when a race ends. Returns true (once) when the session reached [breakMinutes].
  bool recordRace({required int raceMs, required int nowMs, required int breakMinutes}) {
    final start = nowMs - raceMs;
    if (_lastEnd == null || _sessionStart == null || start - _lastEnd! > gapMs) _sessionStart = start;
    _lastEnd = nowMs;
    if (nowMs - _sessionStart! >= breakMinutes * 60 * 1000) {
      _sessionStart = null;
      return true;
    }
    return false;
  }

  int sessionMinutes(int nowMs) => _sessionStart == null ? 0 : (nowMs - _sessionStart!) ~/ 60000;
}
