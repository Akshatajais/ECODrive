import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../providers/driver_score_provider.dart';

class LiveCameraFeedScreen extends StatefulWidget {
  const LiveCameraFeedScreen({
    super.key,
    required this.streamUrl,
    required this.backendLoading,
    required this.backendError,
    required this.onRetryBackend,
  });

  final String? streamUrl;
  final bool backendLoading;
  final String? backendError;
  final Future<void> Function() onRetryBackend;

  @override
  State<LiveCameraFeedScreen> createState() => _LiveCameraFeedScreenState();
}

class _LiveCameraFeedScreenState extends State<LiveCameraFeedScreen> {
  static const _initialReconnectDelay = Duration(seconds: 2);
  static const _maxReconnectDelay = Duration(seconds: 20);

  int _reloadToken = 0;
  bool _hadFrame = false;
  Object? _lastError;

  Timer? _reconnectTimer;
  Duration _reconnectDelay = _initialReconnectDelay;

  _MjpegStreamController? _streamController;

  @override
  void initState() {
    super.initState();
    _maybeStartStream();
  }

  @override
  void didUpdateWidget(covariant LiveCameraFeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamUrl != widget.streamUrl) {
      _maybeStartStream();
    }
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _streamController?.dispose();
    super.dispose();
  }

  bool get _hasBackendUrl => (widget.streamUrl ?? '').trim().isNotEmpty;

  Future<void> _reconnect() async {
    await widget.onRetryBackend();
    _maybeStartStream();
    _connectStream();
  }

  void _maybeStartStream() {
    if (!_hasBackendUrl) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _streamController?.dispose();
      _streamController = null;
      if (mounted) {
        setState(() {
          _hadFrame = false;
          _lastError = null;
          _reloadToken++;
        });
      }
      return;
    }

    _streamController?.dispose();
    _streamController = _MjpegStreamController(
      url: widget.streamUrl!.trim(),
      timeout: const Duration(seconds: 6),
      onFirstFrame: () {
        if (!mounted) return;
        setState(() {
          _hadFrame = true;
          _lastError = null;
        });
      },
      onFrame: () {},
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _lastError = err;
        });
        _scheduleReconnect();
      },
    );

    _connectStream();
  }

  void _connectStream() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectDelay = _initialReconnectDelay;
    if (!_hasBackendUrl || _streamController == null) return;
    setState(() {
      _hadFrame = false;
      _lastError = null;
      _reloadToken++;
    });
    _streamController!.restart(url: widget.streamUrl!.trim());
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null) return;
    _reconnectTimer = Timer(_reconnectDelay, () {
      if (!mounted) return;
      _reconnectTimer = null;
      setState(() => _reloadToken++);
      _reconnectDelay = Duration(
        seconds: (_reconnectDelay.inSeconds * 2).clamp(
          _initialReconnectDelay.inSeconds,
          _maxReconnectDelay.inSeconds,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final driver = context.watch<DriverScoreProvider>();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Camera'),
        actions: [
          IconButton(
            tooltip: 'Reconnect',
            onPressed: _reconnect,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildStreamArea(context),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x88000000),
                              Color(0x14000000),
                              Color(0x00000000),
                            ],
                            stops: [0.0, 0.35, 1.0],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        top: 12,
                        child: _StatusChip(
                          label: _statusText(),
                          tone: _statusTone(),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        top: 6,
                        child: IconButton(
                          onPressed: _reconnect,
                          tooltip: 'Reconnect stream',
                          icon: const Icon(Icons.refresh, color: Colors.white),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.40),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                          ),
                          child: Text(
                            'Live view of smoke exhaust',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _SectionHeader(
                title: 'Smoke monitoring',
                subtitle: 'This feed is used to observe exhaust plume behavior.',
              ),
              const SizedBox(height: 10),
              const _SmokeStatements(),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _reconnect,
                      icon: const Icon(Icons.wifi_tethering),
                      label: const Text('Reconnect'),
                    ),
                  ),
                ],
              ),
              if (driver.error != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Live data: demo',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
              if (!_hasBackendUrl || widget.backendError != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    !_hasBackendUrl
                        ? 'No stream URL detected. Turn on the camera device and ensure the backend is running.'
                        : (widget.backendError ?? 'Camera backend error.'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _ActionCard(
                      icon: Icons.tips_and_updates,
                      title: 'Quick tip',
                      body: 'If smoke looks dense or dark, flag the vehicle for inspection.',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionCard(
                      icon: Icons.shield_outlined,
                      title: 'Safety',
                      body: 'Do not interact with the app while driving.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusText() {
    if (widget.backendLoading) return 'Checking camera…';
    if (!_hasBackendUrl) return 'Camera not connected';
    if (widget.backendError != null) return 'Camera not connected';
    if (_lastError != null) return 'Camera not connected';
    if (_hadFrame) return 'Connected';
    return 'Connecting…';
  }

  _StatusTone _statusTone() {
    if (widget.backendLoading) return _StatusTone.neutral;
    if (!_hasBackendUrl) return _StatusTone.error;
    if (widget.backendError != null) return _StatusTone.error;
    if (_lastError != null) return _StatusTone.error;
    if (_hadFrame) return _StatusTone.good;
    return _StatusTone.neutral;
  }

  Widget _buildStreamArea(BuildContext context) {
    if (widget.backendLoading) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (!_hasBackendUrl || widget.backendError != null) {
      return _MessageView(
        icon: Icons.videocam_off,
        title: 'Camera not connected',
        message: 'Turn on the camera and try reconnecting.',
        primaryActionLabel: 'Reconnect',
        onPrimaryAction: _reconnect,
        tone: _MessageTone.neutral,
      );
    }

    final controller = _streamController;
    if (controller == null) {
      return _MessageView(
        icon: Icons.videocam_off,
        title: 'Starting stream…',
        message: 'If this takes long, try reconnecting.',
        primaryActionLabel: 'Reconnect',
        onPrimaryAction: _reconnect,
        tone: _MessageTone.neutral,
      );
    }

    return _MjpegStreamView(
      key: ValueKey('${widget.streamUrl}::$_reloadToken'),
      controller: controller,
      fit: BoxFit.cover,
      showLoading: !_hadFrame && _lastError == null,
      error: _lastError,
      onReconnectTap: _connectStream,
    );
  }
}

class _MjpegStreamView extends StatelessWidget {
  const _MjpegStreamView({
    super.key,
    required this.controller,
    required this.fit,
    required this.showLoading,
    required this.error,
    required this.onReconnectTap,
  });

  final _MjpegStreamController controller;
  final BoxFit fit;
  final bool showLoading;
  final Object? error;
  final VoidCallback onReconnectTap;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return _MessageView(
        icon: Icons.wifi_off,
        title: 'Stream disconnected',
        message: 'Your backend stream dropped. Reconnect to try again.',
        primaryActionLabel: 'Reconnect',
        onPrimaryAction: onReconnectTap,
        tone: _MessageTone.error,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ValueListenableBuilder<ImageProvider?>(
          valueListenable: controller.image,
          builder: (context, provider, _) {
            if (provider == null) {
              return Container(color: Colors.black);
            }
            return Image(
              image: provider,
              fit: fit,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              isAntiAlias: true,
            );
          },
        ),
        if (showLoading)
          Container(
            color: Colors.black,
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }
}

class _MjpegStreamController {
  _MjpegStreamController({
    required String url,
    required Duration timeout,
    required VoidCallback onFirstFrame,
    required VoidCallback onFrame,
    required ValueChanged<Object> onError,
  })  : _url = url,
        _timeout = timeout,
        _onFirstFrame = onFirstFrame,
        _onFrame = onFrame,
        _onError = onError;

  final Duration _timeout;
  final VoidCallback _onFirstFrame;
  final VoidCallback _onFrame;
  final ValueChanged<Object> _onError;

  final http.Client _client = http.Client();

  String _url;
  bool _disposed = false;
  bool _sentFirstFrame = false;

  StreamSubscription<List<int>>? _sub;
  http.StreamedResponse? _response;

  final ValueNotifier<ImageProvider?> image = ValueNotifier<ImageProvider?>(null);

  Future<void> restart({required String url}) async {
    _url = url;
    _sentFirstFrame = false;
    image.value = null;
    await _stop();
    await _start();
  }

  Future<void> _start() async {
    if (_disposed) return;

    try {
      final request = http.Request('GET', Uri.parse(_url));
      final response = await _client.send(request).timeout(_timeout);
      _response = response;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Stream HTTP ${response.statusCode}');
      }

      final carry = <int>[];
      _sub = response.stream.listen(
        (chunk) {
          if (_disposed) return;
          _parseChunk(chunk, carry);
        },
        onError: (e) {
          if (_disposed) return;
          _onError(e);
        },
        onDone: () {
          if (_disposed) return;
          _onError(StateError('Stream closed'));
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (_disposed) return;
      _onError(e);
    }
  }

  void _parseChunk(List<int> chunk, List<int> carry) {
    // Extract JPEG frames based on SOI (FFD8) and EOI (FFD9).
    for (var i = 0; i < chunk.length - 1; i++) {
      final d0 = chunk[i];
      final d1 = chunk[i + 1];

      if (d0 == 0xFF && d1 == 0xD8) {
        carry
          ..clear()
          ..add(d0);
      } else if (d0 == 0xFF && d1 == 0xD9 && carry.isNotEmpty) {
        carry.addAll([d0, d1]);
        _emitFrame(carry);
        carry.clear();
      } else if (carry.isNotEmpty) {
        carry.add(d0);
        if (i == chunk.length - 2) {
          carry.add(d1);
        }
      }
    }
  }

  void _emitFrame(List<int> frameBytes) {
    if (frameBytes.length < 4) return;
    if (frameBytes[0] != 0xFF || frameBytes[1] != 0xD8) return;
    if (frameBytes[frameBytes.length - 2] != 0xFF ||
        frameBytes[frameBytes.length - 1] != 0xD9) {
      return;
    }

    final bytes = Uint8List.fromList(frameBytes);
    image.value = MemoryImage(bytes);
    _onFrame();

    if (!_sentFirstFrame) {
      _sentFirstFrame = true;
      _onFirstFrame();
    }
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      _response?.stream.drain();
    } catch (_) {}
    _response = null;
  }

  void dispose() {
    _disposed = true;
    image.dispose();
    _stop();
    _client.close();
  }
}

enum _StatusTone { good, neutral, warn, error }

enum _MessageTone { neutral, error }

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.tone});

  final String label;
  final _StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg, icon) = switch (tone) {
      _StatusTone.good => (cs.primaryContainer, cs.onPrimaryContainer, Icons.check_circle),
      _StatusTone.warn => (cs.tertiaryContainer, cs.onTertiaryContainer, Icons.info),
      _StatusTone.error => (cs.errorContainer, cs.onErrorContainer, Icons.error_outline),
      _StatusTone.neutral => (cs.surfaceContainerHighest, cs.onSurfaceVariant, Icons.circle),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.10)),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: cs.onSurfaceVariant,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _SmokeStatements extends StatelessWidget {
  const _SmokeStatements();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: const [
        _StatementChip(
          icon: Icons.blur_on,
          title: 'Monitoring',
          body: 'Smoke opacity',
        ),
        _StatementChip(
          icon: Icons.waves_outlined,
          title: 'Observing',
          body: 'Plume movement',
        ),
        _StatementChip(
          icon: Icons.color_lens_outlined,
          title: 'Checking',
          body: 'Color change',
        ),
        _StatementChip(
          icon: Icons.rule_folder_outlined,
          title: 'Flagging',
          body: 'Dense smoke events',
        ),
      ],
    );
  }
}

class _StatementChip extends StatelessWidget {
  const _StatementChip({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryActionLabel,
    required this.onPrimaryAction,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryActionLabel;
  final VoidCallback onPrimaryAction;
  final _MessageTone tone;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color fg = tone == _MessageTone.error ? cs.onErrorContainer : cs.onSurface;
    final Color bg = tone == _MessageTone.error ? cs.errorContainer : cs.surface;
    final Color sub = tone == _MessageTone.error ? cs.onErrorContainer : cs.onSurfaceVariant;

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 420),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: bg.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: fg.withValues(alpha: 0.12)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 46, color: fg),
                        const SizedBox(height: 10),
                        Text(
                          title,
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          message,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: sub,
                            height: 1.25,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: onPrimaryAction,
                          icon: const Icon(Icons.refresh),
                          label: Text(primaryActionLabel),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

