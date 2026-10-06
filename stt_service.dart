import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 实时语音识别接口。
///
/// Flutter 客户端不保存任何第三方 API Key。
/// 实际部署时，让你的后端提供一个 WebSocket 地址：
///   wss://your-domain.com/realtime-stt
///
/// 客户端发送：
///   {"type":"audio","audio_base64":"...","sample_rate":16000}
///
/// 后端返回：
///   {"type":"partial","text":"你好今天"}
///   {"type":"final","text":"你好，今天我们开始上课。","speaker":"老师"}
///
/// 这样以后可以自由替换 OpenAI/Azure/Google/其他中文 STT 服务。
class RealtimeSttService {
  WebSocketChannel? _socket;
  StreamSubscription? _subscription;
  final _textController = StreamController<SttEvent>.broadcast();

  Stream<SttEvent> get events => _textController.stream;

  Future<void> connect({required String backendUrl}) async {
    if (backendUrl.trim().isEmpty) {
      throw Exception('请在 SttConfig.backendUrl 中配置实时转写后端地址。');
    }
    _socket = WebSocketChannel.connect(Uri.parse(backendUrl));
    await _socket!.ready;
    _subscription = _socket!.stream.listen((raw) {
      try {
        final data = jsonDecode(raw as String) as Map<String, dynamic>;
        final type = data['type']?.toString() ?? '';
        if (type == 'partial') {
          _textController.add(SttEvent.partial(data['text']?.toString() ?? ''));
        } else if (type == 'final') {
          _textController.add(SttEvent.finalText(
            data['text']?.toString() ?? '',
            speaker: data['speaker']?.toString(),
          ));
        } else if (type == 'error') {
          _textController.add(SttEvent.error(data['message']?.toString() ?? '识别服务错误'));
        }
      } catch (_) {
        _textController.add(SttEvent.error('识别服务器返回的数据格式不正确'));
      }
    });
  }

  void sendAudio(Uint8List bytes, {int sampleRate = 16000}) {
    if (_socket == null) return;
    _socket!.sink.add(jsonEncode({
      'type': 'audio',
      'audio_base64': base64Encode(bytes),
      'sample_rate': sampleRate,
    }));
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    await _socket?.sink.close();
    _subscription = null;
    _socket = null;
  }

  Future<void> dispose() async {
    await stop();
    await _textController.close();
  }
}

class SttEvent {
  final String type;
  final String text;
  final String? speaker;
  final String? errorMessage;
  const SttEvent._(this.type, this.text, this.speaker, this.errorMessage);

  factory SttEvent.partial(String text) => SttEvent._('partial', text, null, null);
  factory SttEvent.finalText(String text, {String? speaker}) => SttEvent._('final', text, speaker, null);
  factory SttEvent.error(String message) => SttEvent._('error', '', null, message);

  bool get isPartial => type == 'partial';
  bool get isFinal => type == 'final';
  bool get isError => type == 'error';
}

/// 发布前只需要修改这里，不需要把密钥放进 App。
class SttConfig {
  static const String backendUrl = 'wss://YOUR-DOMAIN.com/realtime-stt';
}
