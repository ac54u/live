import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
// 【注意】这里是 5.1.0 版本的引用方式，和 6.0 不一样，千万别改回去了
import 'package:ffmpeg_kit_flutter_https_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_https_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await [
    Permission.camera,
    Permission.microphone,
    Permission.photos,
    Permission.storage,
    Permission.manageExternalStorage
  ].request();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pro Live Recorder',
      theme: ThemeData.dark(),
      home: const LivePage(),
    );
  }
}

class LivePage extends StatefulWidget {
  const LivePage({super.key});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  final String targetUrl = "https://zh.stripchat.com";
  // 5.1.0 版本同样需要伪装 UA
  final String userAgentStr =
      "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

  String? detectedStreamUrl;
  int currentQualityScore = 0;
  bool isRecording = false;
  String statusText = "等待直播源 (v5.1.0 稳定版)...";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(targetUrl)),
              initialSettings: InAppWebViewSettings(
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                javaScriptEnabled: true,
                domStorageEnabled: true,
                useShouldInterceptRequest: true,
                userAgent: userAgentStr,
                allowsPictureInPictureMediaPlayback: true,
              ),
              shouldInterceptRequest: (controller, request) async {
                String url = request.url.toString();
                if (url.contains(".m3u8")) {
                  int newScore = _getQualityScore(url);
                  if (newScore > currentQualityScore) {
                    // 使用 addPostFrameCallback 避免构建时刷新 UI
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          detectedStreamUrl = url;
                          currentQualityScore = newScore;
                          statusText = "已锁定画质: ${_getQualityLabel(newScore)}";
                        });
                      }
                    });
                  }
                }
                return null;
              },
            ),
            Positioned(
              bottom: 20, left: 20, right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(statusText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildButton(
                          icon: Icons.fiber_manual_record,
                          color: Colors.redAccent,
                          text: "开始录制",
                          onTap: (detectedStreamUrl != null && !isRecording) ? _startRecording : null,
                        ),
                        _buildButton(
                          icon: Icons.stop_circle_outlined,
                          color: isRecording ? Colors.white : Colors.grey,
                          text: "停止保存",
                          onTap: isRecording ? _stopRecording : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _getQualityScore(String url) {
    if (url.contains("source") || url.contains("orig")) return 100;
    if (url.contains("1080p")) return 90;
    if (url.contains("720p")) return 80;
    if (url.contains("480p")) return 60;
    return 10;
  }

  String _getQualityLabel(int score) {
    if (score >= 100) return "🌟 原画";
    if (score >= 90) return "🔥 1080p";
    if (score >= 80) return "✅ 720p";
    return "📺 标清";
  }

  Widget _buildButton({required IconData icon, required Color color, required String text, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: onTap != null ? color : Colors.white24, size: 32),
          const SizedBox(height: 4),
          Text(text, style: TextStyle(color: onTap != null ? Colors.white : Colors.white24, fontSize: 12)),
        ],
      ),
    );
  }

  void _startRecording() async {
    if (detectedStreamUrl == null) return;
    setState(() { isRecording = true; statusText = "🔴 录制中... (请保持前台)"; });
    
    final dir = await getApplicationDocumentsDirectory();
    final outputPath = "${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.mp4";

    // 5.1.0 版本的命令格式完全一样
    String command = '-headers "Referer: https://zh.stripchat.com/" -headers "User-Agent: $userAgentStr" -i "$detectedStreamUrl" -c copy -y "$outputPath"';

    FFmpegKit.executeAsync(command, (session) async {
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode) || ReturnCode.isCancel(returnCode)) {
        _saveToGallery(outputPath);
      } else {
        setState(() { statusText = "❌ 录制失败 (可能是网络问题)"; isRecording = false; });
      }
    });
  }

  void _stopRecording() {
    FFmpegKit.cancel();
    setState(() { isRecording = false; statusText = "正在保存..."; });
  }

  void _saveToGallery(String path) async {
    try {
      File file = File(path);
      if (await file.exists() && await file.length() > 10000) {
        await Gal.putVideo(path);
        setState(() { statusText = "✅ 已保存到相册！"; });
      } else {
        setState(() { statusText = "⚠️ 视频太短或无效"; });
      }
    } catch (e) {
      setState(() { statusText = "保存出错: $e"; });
    }
  }
}
