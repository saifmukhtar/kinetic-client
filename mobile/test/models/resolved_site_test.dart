import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/src/models/resolved_site.dart';

void main() {
  group('ResolvedSite Tests', () {
    test('displayName strips kin:// prefix and .kin suffix', () {
      const site = ResolvedSite(
        kinUrl: 'kin://example.kin',
        targetUrl: 'https://example.com',
        trustStateJson: '{}',
      );

      expect(site.displayName, 'example');
    });

    test('displayName handles missing suffix gracefully', () {
      const site = ResolvedSite(
        kinUrl: 'kin://example',
        targetUrl: 'https://example.com',
        trustStateJson: '{}',
      );

      expect(site.displayName, 'example');
    });

    test('displayName handles http protocol in kinUrl gracefully', () {
      const site = ResolvedSite(
        kinUrl: 'http://example.kin',
        targetUrl: 'https://example.com',
        trustStateJson: '{}',
      );

      // Since it doesn't start with kin://, replaceFirst won't match kin://
      // But it might strip .kin if we only strip suffix.
      expect(site.displayName, 'http://example');
    });
  });
}
