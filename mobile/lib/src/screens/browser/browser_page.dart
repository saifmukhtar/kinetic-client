import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:kinetic/src/models/resolved_site.dart';
import 'package:kinetic/src/rust/api/resolver.dart';
import 'package:kinetic/src/theme/app_theme.dart';
import 'package:kinetic/src/widgets/trust_sheet.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

/// Full-screen browser page that loads a resolved .kin site in a WebView.
/// Features a floating address bar + a morphing sphere navigation button.
class BrowserPage extends StatefulWidget {
  final ResolvedSite site;

  const BrowserPage({super.key, required this.site});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage>
    with TickerProviderStateMixin {
  late final WebViewController _controller;
  bool _isLoading = true;
  int _loadingProgress = 0;

  // Navigation sphere state
  bool _isNavExpanded = false;

  // Animation controllers
  late AnimationController _sphereController;
  late Animation<double> _sphereExpand;
  late Animation<double> _sphereFade;
  late Animation<Alignment> _sphereAlign;

  @override
  void initState() {
    super.initState();

    _sphereController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _sphereExpand = CurvedAnimation(
      parent: _sphereController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    _sphereFade = CurvedAnimation(
      parent: _sphereController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
    );
    _sphereAlign = Tween<Alignment>(
      begin: Alignment.centerRight,
      end: Alignment.center,
    ).animate(CurvedAnimation(
      parent: _sphereController,
      curve: Curves.easeOutCubic,
    ));

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() {
            _isLoading = true;
            _loadingProgress = 0;
          }),
          onProgress: (progress) =>
              setState(() => _loadingProgress = progress),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onHttpError: (error) {
            setState(() {
              _isLoading = false;
              _controller.loadHtmlString(_errorHtml(
                  'Peer Unreachable',
                  'The site failed to load (HTTP ${error.response?.statusCode ?? 502}).'));
            });
          },
          onWebResourceError: (error) {
            setState(() {
              _isLoading = false;
              _controller.loadHtmlString(_errorHtml(
                  'Connection Failed',
                  'Could not connect to the Kinetic peer. The node may be offline.'));
            });
          },
        ),
      )
      ..addJavaScriptChannel(
        'KineticErrorChannel',
        onMessageReceived: (message) async {
          if (message.message == 'retry') {
            setState(() => _isLoading = true);
            try {
              final doc = await resolveKinUrl(kinUrl: widget.site.kinUrl);
              if (doc.targetUrl != null) {
                _controller.loadRequest(Uri.parse(doc.targetUrl!));
              }
            } catch (e) {
              setState(() => _isLoading = false);
            }
          }
        },
      )
      ..loadRequest(Uri.parse(widget.site.targetUrl));
  }

  @override
  void dispose() {
    _sphereController.dispose();
    _controller.clearCache();
    super.dispose();
  }

  void _toggleNav() {
    HapticFeedback.lightImpact();
    setState(() => _isNavExpanded = !_isNavExpanded);
    if (_isNavExpanded) {
      _sphereController.forward();
    } else {
      _sphereController.reverse();
    }
  }

  void _closeNav() {
    if (_isNavExpanded) {
      setState(() => _isNavExpanded = false);
      _sphereController.reverse();
    }
  }

  String _errorHtml(String title, String message) => '''
    <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body { font-family: -apple-system, sans-serif; text-align: center; padding: 40px; background: #0A0A0B; color: #FFFFFF; }
          h1 { font-size: 24px; margin-bottom: 16px; }
          p { font-size: 16px; color: #8F9098; }
          button { padding: 12px 24px; background: #FF4D4D; color: white; border: none; border-radius: 8px; font-size: 16px; margin-top: 24px; cursor: pointer; font-weight: 600; }
        </style>
      </head>
      <body>
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="#FF4D4D" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="8" x2="12" y2="12"></line><line x1="12" y1="16" x2="12.01" y2="16"></line></svg>
        <h1>$title</h1>
        <p>$message</p>
        <button onclick="KineticErrorChannel.postMessage('retry')">Retry Connection</button>
      </body>
    </html>
  ''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // WebView fills the full screen
          SafeArea(
            bottom: false,
            child: WebViewWidget(controller: _controller),
          ),

          // Tap-outside dismisser when nav is expanded
          if (_isNavExpanded)
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeNav,
                behavior: HitTestBehavior.translucent,
                child: Container(color: Colors.transparent),
              ),
            ),

          // Floating bottom bar
          _buildBottomBar(context),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      bottom: bottomPad + 16,
      left: 16,
      right: 16,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          // ── Morphing Sphere / Unified Navigation Panel ────────────────────
          AnimatedBuilder(
            animation: _sphereController,
            builder: (context, child) {
              return _isNavExpanded
                  ? _buildExpandedNav(context)
                  : _buildSphere();
            },
          ),
        ],
      ),
    );
  }

  // The address bar is now only visible when the sphere is expanded
  Widget _buildAddressBar(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border.withOpacity(0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress bar
          if (_isLoading)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: LinearProgressIndicator(
                value: _loadingProgress / 100,
                backgroundColor: Colors.transparent,
                color: AppTheme.primary,
                minHeight: 2,
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                // Back button
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded, size: 18, color: AppTheme.textSecondary),
                  onPressed: () async {
                    if (await _controller.canGoBack()) {
                      _controller.goBack();
                    } else {
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  tooltip: 'Back',
                ),

                // URL + Trust badge
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _closeNav();
                      TrustSheet.show(
                        context,
                        kinName: widget.site.kinUrl,
                        trustStateJson: widget.site.trustStateJson,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.surface.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.site.kinUrl.startsWith('kin://') ? Icons.lock_rounded : Icons.public_rounded,
                            color: widget.site.kinUrl.startsWith('kin://') ? AppTheme.success : AppTheme.textSecondary,
                            size: 13,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              widget.site.kinUrl.startsWith('kin://') ? '${widget.site.displayName}.kin' : widget.site.kinUrl,
                              style: GoogleFonts.firaCode(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Refresh button (inside bar)
                IconButton(
                  icon: _isLoading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary.withOpacity(0.7)),
                        )
                      : const Icon(Icons.refresh_rounded, size: 20, color: AppTheme.textSecondary),
                  onPressed: _isLoading ? null : () => _controller.reload(),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // The collapsed circular sphere button
  Widget _buildSphere() {
    return GestureDetector(
      onTap: _toggleNav,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.primary,
              AppTheme.primaryLight,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withOpacity(0.45),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(
          Icons.apps_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  // The expanded navigation panel that morphs from the sphere
  Widget _buildExpandedNav(BuildContext context) {
    return FadeTransition(
      opacity: _sphereFade,
      child: ScaleTransition(
        scale: _sphereExpand,
        alignment: Alignment.bottomRight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              // Take up most of the screen width for the expanded bar, making it look natural
              width: MediaQuery.of(context).size.width - 32,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.surface.withOpacity(0.92),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                    color: AppTheme.primary.withOpacity(0.3), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.15),
                    blurRadius: 32,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle indicator
                  Container(
                    width: 32,
                    height: 3,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.border.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),

                  // The Address Bar inside the navigation panel
                  _buildAddressBar(context),

                  // Browser tab button (current page — highlighted)
                  _buildNavItem(
                    icon: Icons.language_rounded,
                    label: 'Browser',
                    isActive: true,
                    onTap: _closeNav,
                  ),

                  const SizedBox(height: 6),

                  // Manage Kin button
                  _buildNavItem(
                    icon: Icons.manage_accounts_rounded,
                    label: 'Manage Kin',
                    isActive: false,
                    onTap: () {
                      Navigator.of(context, rootNavigator: true).pop();
                      context.go('/manage');
                    },
                  ),

                  const Divider(
                      height: 16,
                      thickness: 0.5,
                      color: AppTheme.border,
                      indent: 8,
                      endIndent: 8),

                  // Close browser button
                  _buildNavItem(
                    icon: Icons.close_rounded,
                    label: 'Close Browser',
                    isActive: false,
                    isDanger: true,
                    onTap: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    bool isDanger = false,
  }) {
    final color = isDanger
        ? AppTheme.error
        : isActive
            ? AppTheme.primary
            : AppTheme.textSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppTheme.primary.withOpacity(0.12) : null,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 10),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight:
                      isActive ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
