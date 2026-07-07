import 'dart:ui';
import 'package:kinetic/src/constants.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinetic/src/rust/api/resolver.dart';
import 'package:kinetic/src/models/resolved_site.dart';
import 'package:kinetic/src/screens/browser/browser_page.dart';
import 'package:kinetic/src/theme/app_theme.dart';
import 'package:kinetic/src/widgets/kin_address_bar.dart';
import 'package:kinetic/src/providers/daemon_provider.dart';
import 'package:kinetic/src/providers/identity_provider.dart';
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
  IdentityError? _error;

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

    void handleDeepLink(Uri uri) {
      if (uri.scheme == 'kin' || uri.host.endsWith(AppConstants.dotTld)) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Open Deep Link?'),
            content: Text('Do you want to navigate to ${uri.toString()}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _controller.text = uri.toString();
                  _resolve();
                },
                child: const Text('Open'),
              ),
            ],
          ),
        );
      }
    }

    _linkSub = _appLinks.uriLinkStream.listen(handleDeepLink);
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        handleDeepLink(initial);
      }
    } catch (_) {}
  }

  Future<void> _resolve() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });

    var sanitizedInput = input.toLowerCase();
    bool isKinetic = false;

    if (sanitizedInput.startsWith('http://') ||
        sanitizedInput.startsWith('https://')) {
      final uri = Uri.tryParse(sanitizedInput);
      if (uri != null && uri.host.endsWith(AppConstants.dotTld)) {
        sanitizedInput = 'kin://${uri.host}${uri.path}';
        isKinetic = true;
      } else {
        isKinetic = false;
      }
    } else if (sanitizedInput.startsWith('${AppConstants.tld}://')) {
      isKinetic = true;
    } else {
      if (sanitizedInput.endsWith(AppConstants.dotTld) ||
          sanitizedInput.contains('${AppConstants.dotTld}/')) {
        sanitizedInput = 'kin://$sanitizedInput';
        isKinetic = true;
      } else if (sanitizedInput.contains('.')) {
        sanitizedInput = 'https://$sanitizedInput';
        isKinetic = false;
      } else {
        sanitizedInput = 'kin://$sanitizedInput';
        isKinetic = true;
      }
    }

    ResolvedSite? site;

    try {
      if (isKinetic) {
        final uri = Uri.tryParse(sanitizedInput);
        if (uri == null ||
            uri.scheme != 'kin' ||
            uri.host.isEmpty ||
            !RegExp(r'^[a-zA-Z0-9.-]+$').hasMatch(uri.host)) {
          setState(() {
            _loading = false;
            _error = const IdentityError(
              IdentityErrorKind.notFound,
              'Invalid Kinetic URL format.',
            );
          });
          return;
        }

        // Ensure daemon is started
        if (ref.read(daemonProvider).status != DaemonStatus.running) {
          await ref.read(daemonProvider.notifier).startDaemon();
        }

        final doc = await resolveKinUrl(kinUrl: sanitizedInput);

        if (doc.targetUrl == null) {
          setState(() {
            _loading = false;
            _error = const IdentityError(
              IdentityErrorKind.notFound,
              'This name has no hosted site.',
            );
          });
          return;
        }

        site = ResolvedSite(
          kinUrl: sanitizedInput,
          targetUrl: doc.targetUrl!,
          trustStateJson: doc.rawJson,
        );
      } else {
        // Normal web link
        site = ResolvedSite(
          kinUrl: sanitizedInput,
          targetUrl: sanitizedInput,
          trustStateJson: '', // No trust state for normal web
        );
      }

      // Edge Case 99: Omit large trust state from UI cache to prevent OOM
      final cacheSite = ResolvedSite(
        kinUrl: site.kinUrl,
        targetUrl: site.targetUrl,
        trustStateJson: '',
      );

      setState(() {
        _loading = false;
        _recentSites.removeWhere((s) => s.kinUrl == cacheSite.kinUrl);
        _recentSites.insert(0, cacheSite);
        if (_recentSites.length > 5) _recentSites.removeLast();
      });

      if (mounted) {
        // Use a fade transition for a more modern feel
        Navigator.of(context, rootNavigator: true).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                BrowserPage(site: site!),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
          ),
        );
      }
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      IdentityErrorKind kind = IdentityErrorKind.unknown;
      String cleanMsg = msg.split('\n').first; // Strip stacktrace
      if (msg.contains('not found in the Kinetic network')) {
        kind = IdentityErrorKind.notFound;
        cleanMsg =
            "Name '$sanitizedInput' was not found in the Kinetic network. It may be unregistered.";
      } else if (msg.contains('offline') ||
          msg.contains('timed out') ||
          msg.contains('partitioned')) {
        kind = IdentityErrorKind.offline;
        cleanMsg = "You appear to be offline or the network is partitioned.";
      } else if (msg.contains('DHT lookup failed')) {
        kind = IdentityErrorKind.network;
        cleanMsg = "DHT lookup failed. Check your connection.";
      }
      setState(() {
        _loading = false;
        _error = IdentityError(kind, cleanMsg);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          // Background ambient gradient
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.4),
                  radius: 1.5,
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.08),
                    AppTheme.background,
                  ],
                ),
              ),
            ),
          ),

          Center(
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
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.surface.withValues(alpha: 0.5),
                          border: Border.all(
                            color: AppTheme.border.withValues(alpha: 0.5),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              blurRadius: 32,
                              offset: const Offset(0, 16),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/logo.png',
                          width: 80,
                          height: 80,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Kinetic',
                      style: GoogleFonts.outfit(
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                        letterSpacing: -1.0,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'The Decentralized Web',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary.withValues(alpha: 0.8),
                        letterSpacing: 0.5,
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
                    if (_error != null)
                      Builder(
                        builder: (context) {
                          IconData icon = Icons.error_outline_rounded;
                          switch (_error!.kind) {
                            case IdentityErrorKind.notFound:
                              icon = Icons.search_off_rounded;
                              break;
                            case IdentityErrorKind.offline:
                              icon = Icons.wifi_off_rounded;
                              break;
                            case IdentityErrorKind.network:
                              icon = Icons.cloud_off_rounded;
                              break;
                            default:
                              break;
                          }

                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.only(top: 24),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppTheme.error.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(icon, color: AppTheme.error, size: 24),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    _error!.message,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: AppTheme.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                    // Recent sites
                    if (_recentSites.isNotEmpty) ...[
                      const SizedBox(height: 56),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.history_rounded,
                              size: 18,
                              color: AppTheme.textHint,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'RECENT SITES',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textHint,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _recentSites.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final site = _recentSites[index];
                          return _RecentSiteCard(
                            site: site,
                            onTap: () {
                              _controller.text = site.kinUrl;
                              _resolve();
                            },
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 100), // Padding for bottom nav
                  ],
                ),
              ),
            ),
          ),
        ],
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
                color: AppTheme.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.border.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primary.withValues(alpha: 0.2),
                          AppTheme.primaryLight.withValues(alpha: 0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Icon(
                      Icons.public_rounded,
                      color: AppTheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          site.kinUrl.startsWith('${AppConstants.tld}://')
                              ? '${site.displayName}${AppConstants.dotTld}'
                              : site.kinUrl,
                          style: GoogleFonts.firaCode(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (site.kinUrl.startsWith('${AppConstants.tld}://'))
                          const Row(
                            children: [
                              Icon(
                                Icons.verified_rounded,
                                size: 14,
                                color: AppTheme.success,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Verified via Kinetic DHT',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          )
                        else
                          const Row(
                            children: [
                              Icon(
                                Icons.public_rounded,
                                size: 14,
                                color: AppTheme.textHint,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Standard Web Link',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: AppTheme.textHint,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
