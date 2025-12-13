import 'dart:async';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:talktime/core/constants/api_constants.dart';

class SignalingService {
  WebSocketChannel? _channel;
  final String _userId;

  SignalingService(this._userId);

  Stream<String> get onMessage => _channel!.stream;

  Future<void> connect() async {
    final uri = Uri.parse(
      '${ApiConstants.baseUrl.replaceFirst('http', 'ws')}${ApiConstants.signaling}?userId=$_userId',
    );
    _channel = IOWebSocketChannel.connect(uri);
  }

  void send(String message) {
    _channel!.sink.add(message);
  }

  void disconnect() {
    _channel?.sink.close();
  }
}