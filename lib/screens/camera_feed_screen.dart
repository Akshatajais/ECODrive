import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/alert_gallery_provider.dart';

class CameraFeedScreen extends StatefulWidget {
  const CameraFeedScreen({super.key});

  @override
  State<CameraFeedScreen> createState() => _CameraFeedScreenState();
}

class _CameraFeedScreenState extends State<CameraFeedScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AlertGalleryProvider>().startListening();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AlertGalleryProvider>(
      builder: (context, gallery, _) {
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          backgroundColor: cs.surface,
          body: SafeArea(
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 150,
                  backgroundColor: cs.primary,
                  foregroundColor: Colors.white,
                  title: const Text('Snapshots'),
                  actions: [
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: gallery.refresh,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            cs.primary,
                            cs.tertiary,
                          ],
                        ),
                      ),
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'High-emission evidence',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.92),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _subtitleFor(gallery),
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: _TopBar(
                      count: gallery.items.length,
                      loading: gallery.isLoading,
                      onRefresh: gallery.refresh,
                      error: gallery.error,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: RefreshIndicator(
                    onRefresh: gallery.refresh,
                    child: const SizedBox(height: 0),
                  ),
                ),
                _buildBodySliver(context, gallery),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _subtitleFor(AlertGalleryProvider gallery) {
    if (gallery.isLoading) return 'Connecting to Firebase…';
    if (gallery.error != null) return 'Offline (tap refresh)';
    final n = gallery.items.length;
    if (n == 0) return 'Waiting for the next event…';
    return '$n recent snapshot${n == 1 ? '' : 's'}';
  }

  Widget _buildBodySliver(BuildContext context, AlertGalleryProvider gallery) {
    final cs = Theme.of(context).colorScheme;

    if (gallery.isLoading) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (gallery.error != null) {
      return SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverToBoxAdapter(
          child: _EmptyState(
            icon: Icons.cloud_off,
            title: 'Can’t reach Firebase',
            message: gallery.error!,
            actionLabel: 'Try again',
            onAction: gallery.refresh,
          ),
        ),
      );
    }

    final items = gallery.items;
    if (items.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverToBoxAdapter(
          child: _EmptyState(
            icon: Icons.photo_library_outlined,
            title: 'No snapshots yet',
            message:
                'When emissionScore crosses 400, the device will upload a photo here automatically.',
            actionLabel: 'Refresh',
            onAction: gallery.refresh,
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
      sliver: SliverList.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, idx) {
          final item = items[idx];
          final bytes = item.imageBytes;
          final title = item.timestampRaw.isEmpty ? item.id : item.timestampRaw;
          final subtitle = item.timestamp != null
              ? _prettyTime(item.timestamp!)
              : 'Captured during high emission';

          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.96, end: 1),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: bytes == null
                  ? null
                  : () => Navigator.of(context).push(
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) => _SnapshotDetailScreen(item: item),
                          transitionsBuilder: (_, animation, __, child) {
                            return FadeTransition(opacity: animation, child: child);
                          },
                        ),
                      ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cs.surfaceContainerHighest.withValues(alpha: 0.70),
                      cs.surfaceContainerHighest.withValues(alpha: 0.40),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.32)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 10,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(color: Colors.black),
                          if (bytes != null)
                            Hero(
                              tag: 'snap:${item.id}',
                              child: Image.memory(
                                bytes,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.medium,
                              ),
                            )
                          else
                            const Center(
                              child: Icon(Icons.broken_image, color: Colors.white70, size: 42),
                            ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0x8A000000),
                                  Color(0x22000000),
                                  Color(0x00000000),
                                ],
                                stops: [0.0, 0.55, 1.0],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 12,
                            top: 12,
                            child: _Pill(
                              icon: Icons.local_fire_department,
                              label: 'Score ${item.emissionScore}',
                              tone: item.emissionScore >= 400
                                  ? _PillTone.danger
                                  : _PillTone.neutral,
                            ),
                          ),
                          Positioned(
                            right: 12,
                            top: 12,
                            child: _Pill(
                              icon: Icons.photo,
                              label: 'View',
                              tone: _PillTone.neutralDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SnapshotDetailScreen extends StatelessWidget {
  const _SnapshotDetailScreen({required this.item});

  final AlertSnapshot item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bytes = item.imageBytes;
    final title = item.timestampRaw.isEmpty ? 'Snapshot' : item.timestampRaw;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: bytes == null
                    ? const Text('Image data missing', style: TextStyle(color: Colors.white70))
                    : InteractiveViewer(
                        minScale: 1,
                        maxScale: 4,
                        child: Hero(
                          tag: 'snap:${item.id}',
                          child: Image.memory(bytes, fit: BoxFit.contain),
                        ),
                      ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.92),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Row(
                children: [
                  _Pill(
                    icon: Icons.local_fire_department,
                    label: 'Score ${item.emissionScore}',
                    tone: item.emissionScore >= 400 ? _PillTone.danger : _PillTone.neutral,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.timestamp != null ? _prettyTime(item.timestamp!) : 'High emission snapshot',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _prettyTime(DateTime dt) {
  final local = dt.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final y = local.year.toString().padLeft(4, '0');
  final m = two(local.month);
  final d = two(local.day);
  final h = two(local.hour);
  final min = two(local.minute);
  final s = two(local.second);
  return '$y-$m-$d  $h:$min:$s';
}

enum _PillTone { neutral, danger, neutralDark }

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.tone});

  final IconData icon;
  final String label;
  final _PillTone tone;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      _PillTone.danger => (cs.errorContainer, cs.onErrorContainer),
      _PillTone.neutral => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
      _PillTone.neutralDark => (Colors.black.withValues(alpha: 0.45), Colors.white),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.count,
    required this.loading,
    required this.onRefresh,
    required this.error,
  });

  final int count;
  final bool loading;
  final Future<void> Function() onRefresh;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          _Pill(
            icon: Icons.photo_library,
            label: loading ? 'Loading…' : '$count shown',
            tone: _PillTone.neutral,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error != null
                  ? 'Backend error'
                  : 'Newest first • Tap a snapshot to zoom',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.surface,
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, size: 38, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
              height: 1.25,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => onAction(),
            icon: const Icon(Icons.refresh),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

