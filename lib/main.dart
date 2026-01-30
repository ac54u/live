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
      title: 'Ultimate Sniffer',
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
  // 强力伪装：模拟最新的 iPhone Safari
  final String userAgentStr =
      "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1";

  InAppWebViewController? webViewController;
  String? detectedStreamUrl;
  String statusText = "初始化嗅探器...";
  List<String> logs = []; // 调试日志
  Timer? _jsTimer;

  @override
  void dispose() {
    _jsTimer?.cancel();
    super.dispose();
  }

  // 添加日志到屏幕
  void _addLog(String msg) {
    if (logs.length > 5) logs.removeAt(0); // 只保留最近5条
    logs.add(msg);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // 1. 浏览器区域 (占用剩余空间)
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(targetUrl)),
                initialSettings: InAppWebViewSettings(
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  userAgent: userAgentStr,
                  allowsPictureInPictureMediaPlayback: true,
                  // 关键：允许资源加载监听
                  useOnLoadResource: true, 
                ),
                onWebViewCreated: (controller) {
                  webViewController = controller;
                  // 启动 JS 暴力轮询
                  _startJsSniffer();
                },
                // --- 方案 A: 网络层被动监听 (比拦截更稳) ---
                onLoadResource: (controller, resource) {
                  String url = resource.url.toString();
                  _checkUrl(url, "网络层");
                },
              ),
            ),

            // 2. 底部控制台 (显示抓取结果)
            Container(
              height: 180,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                border: const Border(top: BorderSide(color: Colors.white24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 状态标题
                  Row(
                    children: [
                      Icon(
                        detectedStreamUrl != null ? Icons.check_circle : Icons.radar,
                        color: detectedStreamUrl != null ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          detectedStreamUrl != null ? "抓获目标！" : "全频道扫描中...",
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  
                  // 滚动日志区
                  Expanded(
                    child: ListView.builder(
                      reverse: true, // 最新在最下
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        return Text(
                          logs[index],
                          style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace'),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 10),
                  
                  // 复制按钮
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: detectedStreamUrl != null
                          ? () {
                              Clipboard.setData(ClipboardData(text: detectedStreamUrl!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("✅ 地址已复制！去服务器下载吧！")));
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: detectedStreamUrl != null ? Colors.green : Colors.grey[800],
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.copy),
                      label: Text(detectedStreamUrl != null ? "复制直播源" : "暂未发现..."),
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

  // --- 方案 B: JS 暴力提取 (每秒执行一次) ---
  void _startJsSniffer() {
    _jsTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (webViewController == null) return;

      // 1. 尝试获取 <video> 标签的 src
      String? videoSrc = await webViewController?.evaluateJavascript(source: """
        (function() {
          var v = document.querySelector('video');
          if (v) return v.src;
          return null;
        })();
      """);

      if (videoSrc != null && videoSrc.isNotEmpty && videoSrc != "null") {
        if (videoSrc.startsWith("blob:")) {
           _addLog("⚠️ 发现 Blob 加密地址 (无法直接下载): $videoSrc");
        } else {
           _checkUrl(videoSrc, "JS提取");
        }
      }
    });
  }

  // --- 统一检查逻辑 ---
  void _checkUrl(String url, String source) {
    // 过滤掉垃圾信息
    if (url.contains("google") || url.contains("facebook") || url.contains("favicon")) return;

    // 如果发现 m3u8 或者 flv
    if (url.contains(".m3u8") || url.contains(".flv") || url.contains(".mp4")) {
      // 避免重复刷新
      if (detectedStreamUrl != url) {
        
        // 简单的画质判断（如果不含分辨率信息，也认为是源）
        bool isBetter = false;
        if (detectedStreamUrl == null) isBetter = true;
        if (url.contains("720p") || url.contains("1080p") || url.contains("source")) isBetter = true;

        if (isBetter) {
          setState(() {
            detectedStreamUrl = url;
            _addLog("🚀 [$source] 锁定目标: ...${url.substring(url.length - 20)}");
          });
          print("抓取成功: $url");
        }
      }
    } else {
      // 偶尔打印一下普通链接证明在工作
      if (logs.length < 2) _addLog("扫描: ...${url.length > 30 ? url.substring(url.length - 30) : url}");
    }
  }
}
