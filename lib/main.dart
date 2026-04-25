import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_html/flutter_html.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '我的应用',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: '我的应用'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _urlController = TextEditingController();
  String _htmlContent = '<html>\n<head>\n  <title>hello world!</title>\n</head>\n</html>';
  bool _isLoading = false;
  String _currentUrl = '';

  // 统一的请求方法
  Future<void> _fetchWebContent(String url) async {
    if (url.isEmpty) return;

    // 处理相对路径 (如果是 /xxx 或 xxx 这种没有域名的链接，拼上当前域名)
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      if (url.startsWith('/') && _currentUrl.isNotEmpty) {
        final uri = Uri.parse(_currentUrl);
        url = '${uri.scheme}://${uri.host}$url';
      } else if (_currentUrl.isNotEmpty) {
        // 处理类似 'page2.html' 的情况
        final uri = Uri.parse(_currentUrl);
        url = '${uri.scheme}://${uri.host}/${uri.path.substring(0, uri.path.lastIndexOf('/'))}/$url';
      } else {
        return; // 没有基础URL且不是完整链接，无法访问
      }
    }

    // 更新输入框的网址和当前记录的网址
    setState(() {
      _isLoading = true;
      _currentUrl = url;
      _urlController.text = url;
    });

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36'
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        setState(() {
          _htmlContent = response.body;
        });
      } else {
        setState(() {
          _htmlContent = '请求失败，状态码: ${response.statusCode}\n\n${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _htmlContent = '请求出错: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 点击访问按钮触发
  void _onVisitPressed() {
    final url = _urlController.text.trim();
    _fetchWebContent(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      hintText: '输入网址',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (value) => _onVisitPressed(), // 支持键盘回车访问
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _onVisitPressed,
                  child: _isLoading 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('访问'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(width: 2),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Html(
                    data: _htmlContent,
                    style: {
                      "body": Style(
                        fontSize: FontSize(16),
                        color: Colors.black87,
                      ),
                      "a": Style(
                        color: Colors.blue,
                        textDecoration: TextDecoration.underline,
                      ),
                    },
                    // 点击超链接时：在APP内部跳转请求
                    onLinkTap: (url, attributes, element) {
                      if (url != null) {
                        _fetchWebContent(url);
                      }
                    },
                  ),
                ),
              ),
            ),
            if (_currentUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  '当前实际URL: $_currentUrl',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
