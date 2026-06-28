import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinetic/src/rust/api/resolver.dart';
import 'package:kinetic/src/models/resolved_site.dart';
import 'package:kinetic/src/screens/browser/browser_page.dart';
import 'package:kinetic/src/theme/app_theme.dart';
import 'package:kinetic/src/widgets/kin_address_bar.dart';
import 'package:kinetic/src/providers/daemon_provider.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';

/// The Browser tab. Lets users type a .kin name, resolve it, and browse it.
class BrowserTab extends ConsumerStatefulWidget {
  const BrowserTab({super.key});

  @override
  ConsumerState<BrowserTab> createState() => _BrowserTabState();
}

class _BrowserTabState extends ConsumerState<BrowserTab> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  String? _errorMessage;

  // Recent sites (in-memory, last 5)
  final List<ResolvedSite> _recentSites = [];

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _controller.dispose();
    _linkSub?.cancel();
    super.dispose();
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();
    _linkSub = _appLinks.uriLinkStream.listen((uri) {
      if (uri.scheme == 'kin' || uri.host.endsWith('.kin')) {
        _controller.text = uri.toString();
        _resolve();
      }
    });
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null && (initial.scheme == 'kin' || initial.host.endsWith('.kin'))) {
        _controller.text = initial.toString();
        _resolve();
      }
    } catch (_) {}
  }

  Future<void> _resolve() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    // Ensure daemon is started
    if (ref.read(daemonProvider).status != DaemonStatus.running) {
      await ref.read(daemonProvider.notifier).startDaemon();
    }

    try {
      final doc = await resolveKinUrl(kinUrl: input);

      if (doc.targetUrl == null) {
        setState(() {
          _loading = false;
          _errorMessage = 'This name has no hosted site.';
        });
        return;
      }

      final site = ResolvedSite(
        kinUrl: input.startsWith('kin://') ? input : 'kin://$input',
        targetUrl: doc.targetUrl!,
        trustStateJson: doc.rawJson,
      );

      setState(() {
        _loading = false;
        _recentSites.removeWhere((s) => s.kinUrl == site.kinUrl);
        _recentSites.insert(0, site);
        if (_recentSites.length > 5) _recentSites.removeLast();
      });

      if (mounted) {
        // Use a fade transition for a more modern feel
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => BrowserPage(site: site),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo & Title
                Hero(
                  tag: 'kinetic_logo',
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 72,
                    height: 72,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Kinetic',
                  style: GoogleFonts.outfit(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The Decentralized Web',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppTheme.textSecondary,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 48),

                // Address bar
                KinAddressBar(
                  controller: _controller,
                  loading: _loading,
                  onSubmitted: _resolve,
                ),
                
                // Error message
                if (_errorMessage != null)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.error.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppTheme.error,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Recent sites
                if (_recentSites.isNotEmpty) ...[
                  const SizedBox(height: 48),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Recent Sites',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textHint,
                        letterSpacing: 1.0,
                        fontFeatures: const [FontFeature.enable('smcp')],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _recentSites.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final site = _recentSites[index];
                      return _RecentSiteCard(
                        site: site,
                        onTap: () {
                          _controller.text = site.displayName;
                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) => BrowserPage(site: site),
                              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                return FadeTransition(opacity: animation, child: child);
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
                const SizedBox(height: 80), // Padding for bottom nav
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentSiteCard extends StatelessWidget {
  final ResolvedSite site;
  final VoidCallback onTap;

  const _RecentSiteCard({required this.site, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.surface.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.border.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primary.withOpacity(0.2),
                          AppTheme.primaryLight.withOpacity(0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                    ),
                    child: const Icon(Icons.public_rounded, color: AppTheme.primary, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${site.displayName}.kin',
                          style: GoogleFonts.firaCode(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Row(
                          children: [
                            Icon(Icons.verified_rounded, size: 14, color: AppTheme.success),
                            SizedBox(width: 4),
                            Text(
                              'Verified via Kinetic DHT',
                              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppTheme.textHint),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
