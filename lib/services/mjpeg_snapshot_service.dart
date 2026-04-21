import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class MjpegSnapshotService {
  const MjpegSnapshotService({
    http.Client? client,
  }) : _client = client;

  final http.Client? _client;

  Future<Uint8List> fetchSnapshot({
    required Uri streamUri,
    Duration timeout = const Duration(seconds: 6),
    int maxBytes = 2 * 1024 * 1024,
  }) async {
    final client = _client ?? http.Client();
    try {
      final req = http.Request('GET', streamUri);
      final res = await client.send(req).timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw StateError('Stream HTTP ${res.statusCode}');
      }

      final completer = Completer<Uint8List>();
      final carry = <int>[];
      var seenBytes = 0;

      late final StreamSubscription<List<int>> sub;
      sub = res.stream.listen(
        (chunk) {
          if (completer.isCompleted) return;
          seenBytes += chunk.length;
          if (seenBytes > maxBytes) {
            completer.completeError(StateError('Snapshot exceeded maxBytes'));
            sub.cancel();
            return;
          }

          for (var i = 0; i < chunk.length - 1; i++) {
            final d0 = chunk[i];
            final d1 = chunk[i + 1];

            if (d0 == 0xFF && d1 == 0xD8) {
              carry
                ..clear()
                ..add(d0);
            } else if (d0 == 0xFF && d1 == 0xD9 && carry.isNotEmpty) {
              carry.addAll([d0, d1]);
              completer.complete(Uint8List.fromList(carry));
              sub.cancel();
              return;
            } else if (carry.isNotEmpty) {
              carry.add(d0);
              if (i == chunk.length - 2) {
                carry.add(d1);
              }
            }
          }
        },
        onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.completeError(StateError('Stream ended before frame'));
          }
        },
        cancelOnError: true,
      );

      return await completer.future.timeout(timeout);
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }
}

