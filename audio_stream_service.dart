import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';

/// 麦克风 PCM 数据流。
///
/// 注意：不同 record 版本/平台对 PCM stream 的支持略有差异。
/// 生产环境建议锁定依赖版本并按目标 iOS/Android 机型测试。
class AudioStreamService {
  final AudioRecorder recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;

  Future<void> start({
    required void Function(Uint8List bytes) onAudio,
  }) async {
    if (!await recorder.hasPermission()) {
      throw Exception('没有麦克风权限');
    }

    final stream = await recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    ));

    _sub = stream.listen(onAudio);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await recorder.stop();
  }

  Future<void> dispose() async {
    await stop();
    await recorder.dispose();
  }
}
