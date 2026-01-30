import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await [Permission.camera, Permission.microphone].request();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Live Sniffer',
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
  // 必须保留 UA 伪装，否则无法嗅探到手机版的高清流
  final String userAgentStr =
      "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

  String? detectedStreamUrl;
  int currentQualityScore = 0;
  String statusText = "正在分析网页，寻找直播源...";

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
                useShouldInterceptRequest: true, // 开启嗅探
                userAgent: userAgentStr,
                allowsPictureInPictureMediaPlayback: true,
              ),
              // --- 核心嗅探逻辑 ---
              shouldInterceptRequest: (controller, request) async {
                String url = request.url.toString();
                if (url.contains(".m3u8")) {
                  int newScore = _getQualityScore(url);
                  // 只有遇到更好的画质才更新
                  if (newScore > currentQualityScore) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          detectedStreamUrl = url;
                          currentQualityScore = newScore;
                          statusText = "已捕获最高画质: ${_getQualityLabel(newScore)}";
                        });
                      }
                    });
                  }
                }
                return null;
              },
            ),
            
            // --- 底部操作栏 ---
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
                    Text(statusText,
                        style: TextStyle(
                            color: _getScoreColor(currentQualityScore),
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        // 只有抓到链接才允许点击
                        onPressed: detectedStreamUrl != null
                            ? () {
                                Clipboard.setData(
                                    ClipboardData(text: detectedStreamUrl!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("✅ 直播源链接已复制！去服务器下载吧！")));
                              }
                            : null,
                        icon: const Icon(Icons.copy),
                        label: const Text("复制直播源链接 (发送给服务器)"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
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
    if (score >= 100) return "🌟 原画 (Source)";
    if (score >= 90) return "🔥 1080p";
    if (score >= 80) return "✅ 720p";
    return "📺 标清";
  }

  Color _getScoreColor(int score) {
    if (score >= 90) return Colors.purpleAccent;
    if (score >= 80) return Colors.greenAccent;
    return Colors.white70;
  }
}
