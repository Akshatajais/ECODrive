import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/camera_stream_provider.dart';
import 'live_camera_feed_screen.dart';

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
      context.read<CameraStreamProvider>().startListening();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CameraStreamProvider>(
      builder: (context, camera, _) {
        return LiveCameraFeedScreen(
          streamUrl: camera.streamUrl,
          backendLoading: camera.isLoading,
          backendError: camera.error,
          onRetryBackend: camera.refresh,
        );
      },
    );
  }
}

