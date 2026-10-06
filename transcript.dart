class TranscriptSegment {
  final String text;
  final DateTime time;
  final String? speaker;
  final bool finalText;
  TranscriptSegment({
    required this.text,
    required this.time,
    this.speaker,
    this.finalText = false,
  });
}

class TranscriptSession {
  final List<TranscriptSegment> segments = [];
  String get fullText => segments.map((e) => e.text).where((e) => e.trim().isNotEmpty).join(' ');
}
