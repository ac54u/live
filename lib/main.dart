import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';
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

  // 必须保持 UserAgent 一致
  final String userAgentStr =
      "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

  String? detectedStreamUrl;
  int currentQualityScore = 0; // 当前捕捉到的画质分数
  bool isRecording = false;
  String statusText = "等待直播源 (智能寻找最高画质)...";

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
              // --- 核心升级：智能画质打分系统 ---
              shouldInterceptRequest: (controller, request) async {
                String url = request.url.toString();

                // 只关心 m3u8
                if (url.contains(".m3u8")) {
                  // 计算新链接的分数
                  int newScore = _getQualityScore(url);

                  // 如果发现了比当前画质更高的链接，就替换！
                  if (newScore > currentQualityScore) {
                    
                    // 在主线程更新
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          detectedStreamUrl = url;
                          currentQualityScore = newScore; // 更新最高分
                          statusText = "已捕获最高画质: ${_getQualityLabel(newScore)}";
                        });
                        print("🚀 画质升级! 捕获到: ${_getQualityLabel(newScore)} \nURL: $url");
                      }
                    });
                  }
                }
                return null;
              },
            ),

            // --- UI 控制面板 ---
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
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
                    // 显示当前画质标签
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: _getScoreColor(currentQualityScore),
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(statusText,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildButton(
                          icon: Icons.fiber_manual_record,
                          color: Colors.redAccent,
                          text: "开始录制",
                          onTap: (detectedStreamUrl != null && !isRecording)
                              ? _startRecording
                              : null,
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

  // --- 辅助函数：给画质打分 ---
  int _getQualityScore(String url) {
    if (url.contains("source") || url.contains("orig")) return 100; // 原画
    if (url.contains("1080p")) return 90;
    if (url.contains("720p")) return 80;
    if (url.contains("480p")) return 60;
    if (url.contains("240p")) return 40;
    return 10; // 未知画质
  }

  // --- 辅助函数：获取画质名称 ---
  String _getQualityLabel(int score) {
    if (score >= 100) return "🌟 原画 (Source)";
    if (score >= 90) return "🔥 1080p 超清";
    if (score >= 80) return "✅ 720p 高清";
    if (score >= 60) return "📺 480p 标清";
    return "❓ 未知画质";
  }

  Color _getScoreColor(int score) {
    if (score >= 90) return Colors.purple; // 高级画质紫色
    if (score >= 80) return Colors.green;  // 720p 绿色
    return Colors.grey;
  }

  Widget _buildButton(
      {required IconData icon,
      required Color color,
      required String text,
      VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: onTap != null ? color : Colors.white24, size: 32),
          const SizedBox(height: 4),
          Text(text,
              style: TextStyle(
                  color: onTap != null ? Colors.white : Colors.white24,
                  fontSize: 12)),
        ],
      ),
    );
  }

  // --- FFmpeg 录制 (保持 Header 欺骗逻辑) ---
  void _startRecording() async {
    if (detectedStreamUrl == null) return;

    setState(() {
      isRecording = true;
      statusText = "🔴 录制中... (${_getQualityLabel(currentQualityScore)})";
    });

    final dir = await getApplicationDocumentsDirectory();
    final outputPath = "${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.mp4";

    String command =
        '-headers "Referer: https://zh.stripchat.com/" '
        '-headers "User-Agent: $userAgentStr" '
        '-i "$detectedStreamUrl" '
        '-c copy -y "$outputPath"';

    print("执行 FFmpeg: $command");

    FFmpegKit.executeAsync(command, (session) async {
      final returnCode = await session.getReturnCode();
      
      if (ReturnCode.isSuccess(returnCode) || ReturnCode.isCancel(returnCode)) {
        _saveToGallery(outputPath);
      } else {
        setState(() {
          statusText = "❌ 录制失败 (Link失效)";
          isRecording = false;
        });
      }
    });
  }

  void _stopRecording() {
    FFmpegKit.cancel();
    setState(() {
      isRecording = false;
      statusText = "正在处理视频...";
    });
  }

  void _saveToGallery(String path) async {
    try {
      File file = File(path);
      // 放宽限制，大于 10KB 就算成功，防止误判
      if (await file.exists() && await file.length() > 10000) {
        await Gal.putVideo(path);
        setState(() {
          statusText = "✅ 已保存到相册！";
        });
      } else {
        setState(() {
          statusText = "⚠️ 视频无效或为空";
        });
      }
    } catch (e) {
      setState(() {
        statusText = "保存出错: $e";
      });
    }
  }
}
