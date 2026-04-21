import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'mjpeg_snapshot_service.dart';

class EvidenceCaptureService {
  EvidenceCaptureService({
    FirebaseDatabase? database,
    FirebaseStorage? storage,
    http.Client? httpClient,
    MjpegSnapshotService? mjpegSnapshotService,
  })  : _database = database ?? FirebaseDatabase.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _httpClient = httpClient,
        _mjpeg = mjpegSnapshotService ?? MjpegSnapshotService(client: httpClient);

  final FirebaseDatabase _database;
  final FirebaseStorage _storage;
  final http.Client? _httpClient;
  final MjpegSnapshotService _mjpeg;

  Future<void> captureAndStore({
    required String deviceId,
    required double emissionScore,
    required double rawGas,
    required String? streamUrl,
    DateTime? eventTime,
    String source = 'unknown',
    Uri? snapshotUriOverride,
  }) async {
    final now = DateTime.now();
    final ts = (eventTime ?? now).toUtc();

    if (streamUrl == null || streamUrl.trim().isEmpty) {
      throw StateError('No streamUrl available for capture');
    }

    final streamUri = Uri.parse(streamUrl.trim());

    final Uint8List jpgBytes = await _fetchJpegBytes(
      streamUri: streamUri,
      overrideSnapshotUri: snapshotUriOverride,
    );

    final objectPath =
        'evidenceCaptures/$deviceId/${ts.toIso8601String().replaceAll(':', '-')}.jpg';

    final ref = _storage.ref().child(objectPath);
    final task = ref.putData(
      jpgBytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    await task.whenComplete(() {});
    final imageUrl = await ref.getDownloadURL();

    final payload = <String, Object?>{
      'deviceId': deviceId,
      'timestamp': ts.toIso8601String(),
      'arrivalTimestamp': now.toUtc().toIso8601String(),
      'source': source,
      'emissionScore': emissionScore,
      'rawGas': rawGas,
      'imageUrl': imageUrl,
      'storagePath': objectPath,
      'streamUrl': streamUrl.trim(),
    };

    await _database.ref('carEmissions/evidenceCaptures').push().set(payload);

    debugPrint(
      '[EVIDENCE] saved device=$deviceId score=$emissionScore rawGas=$rawGas url=$imageUrl',
    );
  }

  Future<Uint8List> _fetchJpegBytes({
    required Uri streamUri,
    Uri? overrideSnapshotUri,
  }) async {
    final candidates = <Uri>[
      if (overrideSnapshotUri != null) overrideSnapshotUri,
      ..._guessSnapshotUris(streamUri),
    ];

    final client = _httpClient ?? http.Client();
    try {
      for (final uri in candidates) {
        try {
          final res = await client.get(uri).timeout(const Duration(seconds: 5));
          if (res.statusCode >= 200 && res.statusCode < 300 && res.bodyBytes.isNotEmpty) {
            return Uint8List.fromList(res.bodyBytes);
          }
        } catch (_) {
          // try next candidate
        }
      }

      // Fallback: extract one JPEG from MJPEG stream safely.
      return _mjpeg.fetchSnapshot(streamUri: streamUri);
    } finally {
      if (_httpClient == null) client.close();
    }
  }

  List<Uri> _guessSnapshotUris(Uri streamUri) {
    // Common ESP32-CAM patterns:
    // - /stream -> /capture
    // - /mjpeg -> /jpeg or /snapshot
    final path = streamUri.path;
    final base = streamUri.replace(queryParameters: const {});

    Uri? replacePath(String from, String to) {
      if (!path.endsWith(from)) return null;
      return base.replace(path: path.substring(0, path.length - from.length) + to);
    }

    final guessed = <Uri?>[
      replacePath('/stream', '/capture'),
      replacePath('/mjpeg', '/capture'),
      replacePath('/mjpeg', '/snapshot'),
      base.replace(path: path.endsWith('/') ? '${path}capture' : '$path/capture'),
      base.replace(path: path.endsWith('/') ? '${path}snapshot' : '$path/snapshot'),
    ];

    // Keep only distinct, valid URIs.
    final out = <Uri>[];
    for (final u in guessed) {
      if (u == null) continue;
      if (out.any((e) => e.toString() == u.toString())) continue;
      out.add(u);
    }
    return out;
  }
}

