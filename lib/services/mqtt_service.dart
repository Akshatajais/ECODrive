import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  MqttService({
    this.host = 'broker.hivemq.com',
    this.port = 1883,
    this.keepAliveSeconds = 20,
  });

  final String host;
  final int port;
  final int keepAliveSeconds;

  MqttServerClient? _client;
  String? _topic;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;

  final _messagesController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messagesController.stream;

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connectAndSubscribe({
    required String clientId,
    required String topic,
  }) async {
    _topic = topic;

    final client = MqttServerClient.withPort(host, clientId, port);
    _client = client;

    client.setProtocolV311();
    client.logging(on: false);
    client.keepAlivePeriod = keepAliveSeconds;
    client.autoReconnect = true;
    client.resubscribeOnAutoReconnect = true;
    client.onConnected = _onConnected;
    client.onDisconnected = _onDisconnected;
    client.onSubscribed = _onSubscribed;
    client.onAutoReconnect = _onAutoReconnect;
    client.onAutoReconnected = _onAutoReconnected;

    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    try {
      await _updatesSub?.cancel();
      _updatesSub = null;
      await client.connect();
    } catch (e) {
      client.disconnect();
      rethrow;
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      client.disconnect();
      throw StateError(
        'MQTT connect failed: ${client.connectionStatus}',
      );
    }

    _subscribeIfNeeded();
    _bindUpdatesStream();
  }

  void disconnect() {
    _updatesSub?.cancel();
    _updatesSub = null;
    _client?.disconnect();
    _client = null;
    _topic = null;
  }

  void dispose() {
    disconnect();
    _messagesController.close();
  }

  void _subscribeIfNeeded() {
    final client = _client;
    final topic = _topic;
    if (client == null || topic == null) return;
    if (!isConnected) return;
    client.subscribe(topic, MqttQos.atLeastOnce);
  }

  void _bindUpdatesStream() {
    final client = _client;
    if (client == null) return;

    _updatesSub = client.updates?.listen(
      (events) {
        if (events.isEmpty) return;
        final message = events.first.payload as MqttPublishMessage;
        final payload =
            MqttPublishPayload.bytesToStringAsString(message.payload.message);

        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map<String, dynamic>) {
            _messagesController.add(decoded);
          } else if (decoded is Map) {
            _messagesController.add(Map<String, dynamic>.from(decoded));
          } else {
            _messagesController.add({'value': decoded});
          }
        } catch (e) {
          // Keep the stream useful even for non-JSON payloads.
          _messagesController.add({'raw': payload});
          _messagesController.addError(e);
        }
      },
      onError: (e) {
        // Surface stream errors to listeners.
        _messagesController.addError(e);
      },
    );
  }

  void _onConnected() {
    _subscribeIfNeeded();
  }

  void _onDisconnected() {
    _messagesController.addError(StateError('MQTT disconnected'));
  }

  void _onSubscribed(String topic) {}

  void _onAutoReconnect() {}

  void _onAutoReconnected() {
    _subscribeIfNeeded();
  }
}

