/// Data model for a successfully resolved .kin site.
class ResolvedSite {
  final String kinUrl;
  final String targetUrl;
  final String trustStateJson;

  const ResolvedSite({
    required this.kinUrl,
    required this.targetUrl,
    required this.trustStateJson,
  });

  /// Returns the display name without `kin://` prefix.
  String get displayName {
    return kinUrl
        .replaceFirst('kin://', '')
        .replaceAll(RegExp(r'\.kin$'), '')
        .trim();
  }
}
