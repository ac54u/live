import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 启动时请求相机和麦克风权限，防止直播互动时闪退
  await [Permission.camera, Permission.microphone].request();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // 移除右上角 Debug 标签
      title: 'Live Player',
      theme: ThemeData.dark(), // 强制深色模式
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
  // 这里的网址是你指定的直播站
  final String targetUrl = "https://zh.stripchat.com";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // 背景纯黑
      body: SafeArea(
        child: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(targetUrl)),
          initialSettings: InAppWebViewSettings(
            // --- 核心播放配置 ---
            mediaPlaybackRequiresUserGesture: false, // 允许自动播放
            allowsInlineMediaPlayback: true, // 允许内联播放
            javaScriptEnabled: true, // 开启 JS
            domStorageEnabled: true, // 开启本地存储
            // 伪装成 iPhone Safari，防止网站拦截
            userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            supportZoom: false, // 禁止缩放
            allowsPictureInPictureMediaPlayback: true, // 允许画中画
            isInspectable: true,
          ),
          // --- 权限自动同意 ---
          onPermissionRequest: (controller, request) async {
            return PermissionResponse(
              resources: request.resources,
              action: PermissionResponseAction.GRANT,
            );
          },
        ),
      ),
    );
  }
}
