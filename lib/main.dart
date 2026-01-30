import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
// 修改引用：使用 https_gpl 包
import 'package:ffmpeg_kit_flutter_https_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_https_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 启动时请求所有必要权限
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
  // 目标直播网站
  final String targetUrl = "https://zh.stripchat.com";

  // 伪装 UserAgent，必须与 FFmpeg 命令中的一致，否则会报 403 Forbidden
  final String userAgentStr =
      "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

  // 状态变量
  String? detectedStreamUrl; // 当前选中的最佳直播流链接
  int currentQualityScore = 0; // 当前画质评分
  bool isRecording = false; // 是否正在录制
  String statusText = "等待直播源 (智能寻找最高画质)..."; // 屏幕底部提示文字

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // 底层：网页浏览器
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(targetUrl)),
              initialSettings: InAppWebViewSettings(
                mediaPlaybackRequiresUserGesture: false, // 自动播放
                allowsInlineMediaPlayback: true, // 内联播放
                javaScriptEnabled: true, // 开启 JS
                domStorageEnabled: true, // 开启存储
                useShouldInterceptRequest: true, // 【核心】开启请求拦截以嗅探
                userAgent: userAgentStr, // 设置伪装 UA
                allowsPictureInPictureMediaPlayback: true, // 画中画
              ),
              // 【核心逻辑】智能画质嗅探
              shouldInterceptRequest: (controller, request) async {
                String url = request.url.toString();

                // 只筛选 .m3u8 直播流
                if (url.contains(".m3u8")) {
                  // 计算当前拦截到的链接画质分数
                  int newScore = _getQualityScore(url);

                  // 如果发现了比当前已锁定的画质更好的链接，则替换
                  // (例如：从 720p 升级到 1080p)
                  if (newScore > currentQualityScore) {
                    // 必须在主线程更新 UI
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          detectedStreamUrl = url;
                          currentQualityScore = newScore;
                          statusText = "已捕获最高画质: ${_getQualityLabel(newScore)}";
                        });
                        // 控制台打印日志，方便调试
                        print("🚀 画质升级! 捕获到: ${_getQualityLabel(newScore)} \nURL: $url");
                      }
                    });
                  }
                }
                return null; // 允许请求正常通过，不阻断网页加载
              },
            ),

            // 上层：控制面板
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85), // 半透明背景
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12), // 微弱边框
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
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                    ),
                    const SizedBox(height: 12),
                    // 按钮区域
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // 录制按钮
                        _buildButton(
                          icon: Icons.fiber_manual_record,
                          color: Colors.redAccent,
                          text: "开始录制",
                          // 只有抓到链接且未录制时才可用
                          onTap: (detectedStreamUrl != null && !isRecording)
                              ? _startRecording
                              : null,
                        ),
                        // 停止按钮
                        _buildButton(
                          icon: Icons.stop_circle_outlined,
                          color: isRecording ? Colors.white : Colors.grey,
                          text: "停止保存",
                          // 只有录制中才可用
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

  // --- 辅助函数：根据 URL 关键词给画质打分 ---
  int _getQualityScore(String url) {
    if (url.contains("source") || url.contains("orig")) return 100; // 原画
    if (url.contains("1080p")) return 90; // 1080p
    if (url.contains("720p")) return 80;  // 720p
    if (url.contains("480p")) return 60;  // 480p
    if (url.contains("240p")) return 40;  // 240p
    return 10; // 未知画质
  }

  // --- 辅助函数：获取画质显示的名称 ---
  String _getQualityLabel(int score) {
    if (score >= 100) return "🌟 原画 (Source)";
    if (score >= 90) return "🔥 1080p 超清";
    if (score >= 80) return "✅ 720p 高清";
    if (score >= 60) return "📺 480p 标清";
    return "❓ 未知画质";
  }

  // --- 辅助函数：根据分数返回颜色 ---
  Color _getScoreColor(int score) {
    if (score >= 90) return Colors.purple; // 高级画质紫色
    if (score >= 80) return Colors.green;  // 720p 绿色
    return Colors.grey;
  }

  // --- 辅助函数：构建按钮组件 ---
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

  // --- 核心功能：开始录制 (FFmpeg) ---
  void _startRecording() async {
    if (detectedStreamUrl == null) return;

    setState(() {
      isRecording = true;
      statusText = "🔴 录制中... (${_getQualityLabel(currentQualityScore)})";
    });

    // 1. 获取 App 文档目录，设置保存路径
    final dir = await getApplicationDocumentsDirectory();
    final outputPath = "${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.mp4";

    // 2. 构建 FFmpeg 命令
    // -headers: 必须添加 Referer 和 UA，防止服务器 403 拒绝访问
    // -i: 输入流地址
    // -c copy: 直接流复制（不重新编码，画质无损，速度快，不发热）
    // -y: 覆盖同名文件
    String command =
        '-headers "Referer: https://zh.stripchat.com/" '
        '-headers "User-Agent: $userAgentStr" '
        '-i "$detectedStreamUrl" '
        '-c copy -y "$outputPath"';

    print("执行 FFmpeg 命令: $command");

    // 3. 异步执行 FFmpeg
    FFmpegKit.executeAsync(command, (session) async {
      final returnCode = await session.getReturnCode();
      
      // 成功 (0) 或被用户取消 (255) 都视为正常结束，尝试保存视频
      if (ReturnCode.isSuccess(returnCode) || ReturnCode.isCancel(returnCode)) {
        _saveToGallery(outputPath);
      } else {
        // 失败
        final failLog = await session.getAllLogsAsString();
        print("录制失败日志: $failLog");
        setState(() {
          statusText = "❌ 录制失败 (可能链接失效)";
          isRecording = false;
        });
      }
    });
  }

  // --- 核心功能：停止录制 ---
  void _stopRecording() {
    FFmpegKit.cancel(); // 向 FFmpeg 发送取消信号，这会触发上面的 executeAsync 回调
    setState(() {
      isRecording = false;
      statusText = "正在处理视频...";
    });
  }

  // --- 核心功能：保存到系统相册 ---
  void _saveToGallery(String path) async {
    try {
      File file = File(path);
      // 检查文件是否存在，且大小大于 10KB (防止保存无效的空文件)
      if (await file.exists() && await file.length() > 10000) {
        await Gal.putVideo(path);
        setState(() {
          statusText = "✅ 已保存到相册！";
        });
        // 可选：保存后删除 App 内部的临时文件以节省空间
        // await file.delete(); 
      } else {
        setState(() {
          statusText = "⚠️ 视频太短或无效，未保存";
        });
      }
    } catch (e) {
      setState(() {
        statusText = "保存出错: $e";
      });
    }
  }
}
