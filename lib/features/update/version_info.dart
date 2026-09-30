/// Contents of version.json published by the release workflow (used for APKs installed outside Google Play).
class VersionInfo {
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final int size;
  final String sha256;
  final Map<String, String> notes;
  final int minSupportedVersion;
  final bool mandatory;
  final DateTime? publishedAt;
  const VersionInfo({required this.versionCode, required this.versionName, required this.apkUrl, required this.size, required this.sha256, required this.notes, required this.minSupportedVersion, required this.mandatory, this.publishedAt});

  static final _hex = RegExp(r'^[0-9a-f]{64}$');
  static const allowedHostSuffixes = ['github.com', 'githubusercontent.com', 'github.io'];

  /// Parses and validates; returns null for anything malformed or pointing at an untrusted host.
  static VersionInfo? tryParse(dynamic j) {
    if (j is! Map) return null;
    try {
      final code = j['versionCode'];
      final url = j['apkUrl'];
      final sha = (j['sha256'] as String?)?.toLowerCase();
      final size = j['size'];
      if (code is! int || code < 1 || url is! String || size is! int || size < 100000 || sha == null || !_hex.hasMatch(sha)) return null;
      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https' || !trustedHost(uri.host)) return null;
      final notes = <String, String>{};
      final n = j['notes'];
      if (n is Map) {
        n.forEach((k, v) {
          if (v is String) notes[k.toString()] = v;
        });
      }
      final min = j['minSupportedVersion'];
      return VersionInfo(
        versionCode: code,
        versionName: (j['versionName'] as String?) ?? '$code',
        apkUrl: url,
        size: size,
        sha256: sha,
        notes: notes,
        minSupportedVersion: min is int ? min : 1,
        mandatory: j['mandatory'] == true,
        publishedAt: DateTime.tryParse((j['publishedAt'] as String?) ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  static bool trustedHost(String host) {
    final h = host.toLowerCase();
    return allowedHostSuffixes.any((s) => h == s || h.endsWith('.$s'));
  }

  String get notesAr => notes['ar'] ?? notes['en'] ?? '';
  String get sizeLabel => size >= 1048576 ? '${(size / 1048576).toStringAsFixed(1)} MB' : '${(size / 1024).toStringAsFixed(0)} KB';

  /// True when this update must be installed before the app can be used.
  bool isMandatoryFor(int currentCode, {int remoteMin = 0}) => mandatory || currentCode < minSupportedVersion || currentCode < remoteMin;
}
