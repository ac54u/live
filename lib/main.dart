import 'dart:async';
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
      title: 'Smart Reconstructor',
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
  final String userAgentStr =
      "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1";

  InAppWebViewController? webViewController;
  String? detectedStreamUrl;
  String statusText = "初始化... (请点击网页播放按钮)";
  List<String> logs = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(targetUrl)),
                    initialSettings: InAppWebViewSettings(
                      mediaPlaybackRequiresUserGesture: false,
                      allowsInlineMediaPlayback: true,
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      userAgent: userAgentStr,
                      allowsPictureInPictureMediaPlayback: true,
                      useOnLoadResource: true, // 开启监听
                    ),
                    onWebViewCreated: (controller) {
                      webViewController = controller;
                    },
                    // --- 核心：既抓 m3u8，也抓 mp4 进行反推 ---
                    onLoadResource: (controller, resource) {
                      String url = resource.url.toString();
                      _analyzeUrl(url);
                    },
                  ),
                  // 刷新按钮 (如果没抓到，点这个重来)
                  Positioned(
                    right: 10,
                    top: 10,
                    child: IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white, size: 30),
                      onPressed: () {
                        webViewController?.reload();
                        setState(() {
                          detectedStreamUrl = null;
                          logs.clear();
                          statusText = "已刷新页面，正在重新捕捉...";
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            // 底部控制台
            Container(
              height: 200,
              padding: const EdgeInsets.all(12),
              color: Colors.grey[900],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(statusText,
                      style: TextStyle(
                          color: detectedStreamUrl != null ? Colors.greenAccent : Colors.orangeAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  const Divider(color: Colors.white24),
                  Expanded(
                    child: ListView.builder(
                      reverse: true, // 最新的在最上面
                      itemCount: logs.length,
                      itemBuilder: (context, index) => Text(logs[index],
                          style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: detectedStreamUrl != null
                          ? () {
                              Clipboard.setData(ClipboardData(text: detectedStreamUrl!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("✅ m3u8 链接已复制！")));
                            }
                          : null,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                      icon: const Icon(Icons.copy, color: Colors.white),
                      label: const Text("复制 m3u8 链接", style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _analyzeUrl(String url) {
    // 1. 如果直接抓到了 m3u8
    if (url.contains(".m3u8") && !url.contains("master")) {
      _lockTarget(url, "直接捕获");
      return;
    }

    // 2. 如果只抓到了 mp4，尝试“逆向推导”
    // 你的 mp4 格式通常是: .../226683119_720p_h264_xxx.mp4
    // 我们要把它变成: .../226683119_720p.m3u8
    if (url.contains(".mp4") && url.contains("_h264_")) {
      try {
        // 逻辑：找到 "_h264_" 的位置，把后面全切掉，换成 ".m3u8"
        int splitIndex = url.indexOf("_h264_");
        if (splitIndex > 0) {
          String guessedUrl = "${url.substring(0, splitIndex)}.m3u8";
          _lockTarget(guessedUrl, "智能推导(从mp4)");
        }
      } catch (e) {
        // 忽略解析错误
      }
    }
    
    // 记录日志 (只显示 mp4 和 m3u8)
    if (url.contains(".mp4") || url.contains(".m3u8")) {
      if (logs.length > 20) logs.removeAt(0);
      String cleanUrl = url.split('/').last; // 只显示文件名
      logs.add("扫描: $cleanUrl");
      if (mounted) setState(() {});
    }
  }

  void _lockTarget(String url, String method) {
    // 避免重复更新
    if (detectedStreamUrl == url) return;

    // 优先保留 720p/1080p，忽略低画质
    if (detectedStreamUrl != null && (url.contains("240p") || url.contains("480p"))) return;

    setState(() {
      detectedStreamUrl = url;
      statusText = "✅ 成功获取链接 ($method)\n${url.split('/').last}";
      logs.add(">>> 锁定目标: $url");
    });
  }
}
