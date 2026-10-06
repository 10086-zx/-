import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'models/transcript.dart';
import 'services/audio_stream_service.dart';
import 'services/stt_service.dart';

void main() => runApp(const VoiceNoteApp());

class VoiceNoteApp extends StatelessWidget {
  const VoiceNoteApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner:false,
    title:'声记',
    theme:ThemeData(
      useMaterial3:true,
      colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF5B5FEF)),
      scaffoldBackgroundColor:const Color(0xFFF7F7FB),
    ),
    home:const HomePage(),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context)=>Scaffold(
    body:SafeArea(
      child:ListView(
        padding:const EdgeInsets.all(20),
        children:[
          const Text('声记',style:TextStyle(fontSize:32,fontWeight:FontWeight.w800)),
          const SizedBox(height:6),
          const Text('课堂与会议实时语音转文字',style:TextStyle(color:Colors.black54)),
          const SizedBox(height:25),
          _modeCard(context,'课堂',Icons.menu_book_rounded,'老师讲课实时变成文字'),
          const SizedBox(height:12),
          _modeCard(context,'会议',Icons.groups_rounded,'会议讨论实时转录'),
          const SizedBox(height:24),
          Card(
            elevation:0,
            child:Padding(
              padding:const EdgeInsets.all(18),
              child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                const Text('V3 核心升级',style:TextStyle(fontWeight:FontWeight.bold,fontSize:17)),
                const SizedBox(height:12),
                _row(Icons.bolt,'实时转写','讲话时文字持续出现'),
                _row(Icons.people_outline,'说话人','后端支持时可标记老师/学生/发言人'),
                _row(Icons.cloud_off,'本地录音','即使转写服务暂时不可用，也可以保留录音'),
              ])
            )
          ),
        ],
      )
    )
  );

  Widget _modeCard(BuildContext context,String mode,IconData icon,String desc)=>Card(
    elevation:0,
    child:ListTile(
      contentPadding:const EdgeInsets.all(16),
      leading:CircleAvatar(radius:27,backgroundColor:const Color(0xFFEDEBFF),child:Icon(icon,color:const Color(0xFF5B5FEF))),
      title:Text(mode,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
      subtitle:Padding(padding:const EdgeInsets.only(top:4),child:Text(desc)),
      trailing:const Icon(Icons.arrow_forward_ios_rounded,size:16),
      onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>LiveTranscriptionPage(mode:mode))),
    )
  );
  Widget _row(IconData i,String t,String d)=>Padding(
    padding:const EdgeInsets.only(bottom:12),
    child:Row(children:[Icon(i,color:const Color(0xFF5B5FEF)),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(t,style:const TextStyle(fontWeight:FontWeight.w600)),Text(d,style:const TextStyle(fontSize:12,color:Colors.black45))]))])
  );
}

class LiveTranscriptionPage extends StatefulWidget {
  final String mode;
  const LiveTranscriptionPage({super.key,required this.mode});
  @override State<LiveTranscriptionPage> createState()=>_LiveTranscriptionPageState();
}

class _LiveTranscriptionPageState extends State<LiveTranscriptionPage> {
  final AudioRecorder fileRecorder=AudioRecorder();
  final AudioStreamService audio=AudioStreamService();
  final RealtimeSttService stt=RealtimeSttService();
  final TranscriptSession session=TranscriptSession();
  StreamSubscription<SttEvent>? sttSub;
  Timer? timer;
  int seconds=0;
  bool running=false;
  bool paused=false;
  bool connecting=false;
  String partial='';
  String? audioPath;
  String status='点击开始，实时文字会显示在这里';
  final ScrollController scroll=ScrollController();

  @override void initState(){
    super.initState();
    sttSub=stt.events.listen(_onStt);
  }

  void _onStt(SttEvent e){
    if(!mounted)return;
    if(e.isPartial){
      setState(()=>partial=e.text);
    }else if(e.isFinal){
      if(e.text.trim().isNotEmpty){
        session.segments.add(TranscriptSegment(text:e.text.trim(),time:DateTime.now(),speaker:e.speaker,finalText:true));
      }
      setState(()=>partial='');
      Future.delayed(const Duration(milliseconds:80),(){
        if(scroll.hasClients)scroll.animateTo(scroll.position.maxScrollExtent,duration:const Duration(milliseconds:200),curve:Curves.easeOut);
      });
    }else if(e.isError){
      setState(()=>status=e.errorMessage??'识别错误');
    }
  }

  Future<void> start() async {
    final permission=await Permission.microphone.request();
    if(!permission.isGranted){
      setState(()=>status='请允许麦克风权限');
      return;
    }
    setState(()=>connecting=true);
    try{
      // 本地录音文件：即使 STT 后端不可用，也不会丢失课堂/会议音频。
      final dir=await getApplicationDocumentsDirectory();
      audioPath='${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await fileRecorder.start(const RecordConfig(
        encoder:AudioEncoder.aacLc,bitRate:128000,sampleRate:44100,numChannels:1,
      ),path:audioPath!);

      // 实时 PCM 流用于 STT。
      await stt.connect(backendUrl:SttConfig.backendUrl);
      await audio.start(onAudio:(bytes){
        stt.sendAudio(bytes,sampleRate:16000);
      });

      timer=Timer.periodic(const Duration(seconds:1),(_){
        if(mounted&&!paused)setState(()=>seconds++);
      });
      setState((){
        running=true; paused=false; connecting=false;
        status='正在实时转写';
      });
    }catch(e){
      setState(()=>connecting=false);
      // 录音本地可用，但如果 STT 后端没配置则给出明确提示。
      setState(()=>status='录音已准备；实时转写服务尚未配置');
      if(audioPath!=null && await File(audioPath!).exists()){
        // 保留已创建的文件
      }
    }
  }

  Future<void> pauseResume() async {
    if(!running)return;
    if(paused){
      await fileRecorder.resume();
      setState(()=>paused=false);
    }else{
      await fileRecorder.pause();
      setState(()=>paused=true);
    }
  }

  Future<void> stop() async {
    timer?.cancel();
    await audio.stop();
    await stt.stop();
    final saved=await fileRecorder.stop();
    audioPath=saved??audioPath;
    if(mounted)setState(()=>running=false);
  }

  @override void dispose(){
    timer?.cancel();
    sttSub?.cancel();
    audio.dispose();
    stt.dispose();
    fileRecorder.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(
      title:Text('${widget.mode} · 实时转写'),
      backgroundColor:Colors.transparent,
      elevation:0,
      actions:[IconButton(onPressed:running?null:()=>Navigator.pop(context),icon:const Icon(Icons.close))]
    ),
    body:Column(children:[
      const SizedBox(height:4),
      Text(_fmt(seconds),style:const TextStyle(fontSize:38,fontWeight:FontWeight.w800)),
      const SizedBox(height:5),
      Row(mainAxisAlignment:MainAxisAlignment.center,children:[
        Container(width:9,height:9,decoration:BoxDecoration(
          color:running&&!paused?Colors.red:Colors.grey,shape:BoxShape.circle)),
        const SizedBox(width:7),
        Text(connecting?'连接转写服务…':status,style:const TextStyle(color:Colors.black54)),
      ]),
      const SizedBox(height:18),
      Expanded(
        child:Container(
          margin:const EdgeInsets.symmetric(horizontal:16),
          padding:const EdgeInsets.fromLTRB(18,14,18,18),
          decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(22)),
          child:Column(children:[
            Row(children:[
              const Icon(Icons.subtitles_rounded,color:Color(0xFF5B5FEF)),
              const SizedBox(width:8),
              const Text('实时文字',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
              const Spacer(),
              if(running)const Text('LIVE',style:TextStyle(color:Colors.red,fontWeight:FontWeight.bold))
            ]),
            const Divider(height:22),
            Expanded(child:ListView(
              controller:scroll,
              children:[
                ...session.segments.map((s)=>_segment(s)),
                if(partial.isNotEmpty)_partial(partial),
                if(session.segments.isEmpty&&partial.isEmpty)
                  const Padding(
                    padding:EdgeInsets.only(top:80),
                    child:Text('开始讲话后，识别出来的文字会实时显示在这里。\n\n支持中文课堂、会议场景。\n建议手机靠近说话人放置。',textAlign:TextAlign.center,style:TextStyle(color:Colors.black38,height:1.6))
                  )
              ],
            ))
          ])
        )
      ),
      const SizedBox(height:12),
      if(session.segments.isNotEmpty)
        Padding(
          padding:const EdgeInsets.symmetric(horizontal:20),
          child:Row(children:[
            const Icon(Icons.auto_awesome,size:18,color:Color(0xFF5B5FEF)),
            const SizedBox(width:7),
            const Expanded(child:Text('AI 总结入口已保留，录音结束后可生成摘要。',style:TextStyle(fontSize:12,color:Colors.black45))),
          ])
        ),
      const SizedBox(height:12),
      Row(mainAxisAlignment:MainAxisAlignment.center,children:[
        if(!running)
          FilledButton.icon(
            onPressed:connecting?null:start,
            icon:const Icon(Icons.mic),
            label:const Text('开始实时转写'),
          )
        else ...[
          OutlinedButton(
            onPressed:pauseResume,
            child:Icon(paused?Icons.play_arrow_rounded:Icons.pause_rounded)
          ),
          const SizedBox(width:20),
          FilledButton(
            onPressed:stop,
            style:FilledButton.styleFrom(backgroundColor:Colors.red),
            child:const Icon(Icons.stop_rounded)
          )
        ]
      ]),
      const SizedBox(height:22),
    ])
  );

  Widget _segment(TranscriptSegment s)=>Padding(
    padding:const EdgeInsets.only(bottom:16),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      if(s.speaker!=null)Text(s.speaker!,style:const TextStyle(fontSize:12,fontWeight:FontWeight.bold,color:Color(0xFF5B5FEF))),
      const SizedBox(height:3),
      Text(s.text,style:const TextStyle(fontSize:16,height:1.5)),
    ])
  );

  Widget _partial(String t)=>Padding(
    padding:const EdgeInsets.only(bottom:16),
    child:Text(t,style:const TextStyle(fontSize:16,height:1.5,color:Colors.black38))
  );

  String _fmt(int s)=>'${(s~/3600).toString().padLeft(2,'0')}:${((s%3600)~/60).toString().padLeft(2,'0')}:${(s%60).toString().padLeft(2,'0')}';
}
