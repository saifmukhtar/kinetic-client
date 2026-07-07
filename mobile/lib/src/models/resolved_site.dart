import 'package:kinetic/src/constants.dart';

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

  String get displayName {
    return kinUrl
        .replaceFirst('${AppConstants.tld}://', '')
        .replaceAll(RegExp('\\${AppConstants.dotTld}\$'), '')
        .trim();
  }
}
