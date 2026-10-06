# 声记 V3：实时语音转文字

## 这一版的重点
V3 不再把 AI 总结当核心，而是把核心体验放在：
**手机麦克风 → PCM 音频流 → WebSocket → 后端 Speech-to-Text → partial/final 文字 → App 实时显示**

同时保留一份本地 M4A 录音，防止转写服务中断导致音频丢失。

## 需要后端
Flutter App 不应该直接携带第三方 STT API Key。
需要一个很薄的 WebSocket 后端：

客户端 -> `wss://你的域名/realtime-stt`

客户端发送：
```json
{"type":"audio","audio_base64":"...","sample_rate":16000}
```

后端返回：
```json
{"type":"partial","text":"我们今天"}
{"type":"final","text":"我们今天开始学习微积分。","speaker":"老师"}
```

然后在 `lib/services/stt_service.dart`：
```dart
static const String backendUrl = 'wss://YOUR-DOMAIN.com/realtime-stt';
```
替换成自己的后端地址。

## 后端应该做什么
1. 接收 WebSocket PCM 16-bit mono 16kHz
2. 将音频流转发到实际 Speech-to-Text 服务
3. 将临时结果返回为 `partial`
4. 将确定结果返回为 `final`
5. 可选：返回 `speaker`

第三方 STT 可以以后替换，不影响 App UI。

## Android
需要：
`android.permission.RECORD_AUDIO`

## iOS
Info.plist：
```xml
<key>NSMicrophoneUsageDescription</key>
<string>声记需要使用麦克风录制课堂和会议内容。</string>
```

## 重要说明
这个压缩包已经把“实时转写客户端”完整搭起来，但没有伪造一个不存在的云端识别服务。
如果不配置 WebSocket 后端，App 仍可录音，但会提示“实时转写服务尚未配置”。


## V3 存储管理升级

新增“录音管理”页面：
- 查看已保存录音及占用空间
- 勾选多条录音后批量删除
- 单条录音删除
- 一键清理应用产生的临时垃圾文件（`.tmp`、`.partial`、`.part`、`temp_`、`stt_`、`pcm_`），不会主动删除已登记的正式录音
- 自动清理失效的录音索引
- 自动扫描早期 V3 已产生的 `voice_*.m4a`，纳入可删除列表
- 显示录音数量和总占用空间

注意：本版本仍需要 Flutter/Android SDK 才能编译成 APK；实时转写仍需要配置 V3 的 WebSocket STT 后端。
