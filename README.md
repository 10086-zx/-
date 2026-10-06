# 声记 V3 — 实时语音转文字 + 存储管理（Android 完整工程）

这是 V3 的 Android 工程增强版，在原有 Flutter 实时录音/实时转写/录音清理功能基础上补齐了 `android/` 原生工程目录。

## 已包含

- Flutter Android 工程结构
- Android Gradle / Kotlin 配置
- AndroidManifest.xml
- Kotlin MainActivity
- 麦克风权限
- Internet 权限
- Android 13+ 通知权限
- Android 14+ 麦克风前台服务权限声明
- Wake Lock 权限
- 手机/平板自适应所需的 Flutter Activity 配置
- Release 构建配置
- 原有实时转写、录音保存、垃圾文件清理、选择删除录音功能

## 第一次构建

在安装了 Flutter SDK、Android SDK 和 JDK 17 的电脑上：

```bash
flutter pub get
flutter doctor
flutter run
```

或者：

```bash
flutter build apk --release
```

Android SDK / Flutter SDK 路径由 `android/local.properties` 提供。可以参考 `android/local.properties.example`。

## 注意：Gradle Wrapper

当前打包环境没有 Flutter/Android SDK，也没有可复用的 `gradle-wrapper.jar`，且无法从网络下载。因此本压缩包包含 `gradlew`、`gradlew.bat` 和 `gradle-wrapper.properties`，但不伪造或内置缺失的二进制 `gradle-wrapper.jar`。

如果使用 Android Studio 打开项目，Android Studio 可以使用其 Gradle 支持完成同步；也可以在完整 Flutter 环境中重新生成 wrapper：

```bash
cd android
gradle wrapper --gradle-version 8.9
```

如果电脑已经安装 Flutter，最简单的方法是直接执行：

```bash
flutter create .
```

Flutter 会补齐标准 Android 工程缺失的 wrapper 文件；然后保留本项目的 `lib/`、`pubspec.yaml` 和 Android 配置即可。

## 实时转写后端

V3 的实时转写客户端仍然通过 `lib/services/stt_service.dart` 连接 WebSocket STT 后端。不要把第三方 API Secret 直接写入 APK。
