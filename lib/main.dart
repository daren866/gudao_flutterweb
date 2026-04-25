import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

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

  Future<void> _fetchWebContent() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isLoading = true;
      _currentUrl = url;
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
          _currentUrl = url;
        });
      } else if (response.statusCode >= 300 && response.statusCode < 400) {
        final redirectUrl = response.headers['location'];
        if (redirectUrl != null) {
          setState(() {
            _htmlContent = '重定向到: $redirectUrl';
            _currentUrl = redirectUrl;
          });
          await _fetchWebContentWithUrl(redirectUrl);
        } else {
          setState(() {
            _htmlContent = '重定向响应，但未找到location头';
          });
        }
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

  Future<void> _fetchWebContentWithUrl(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36'
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          _htmlContent = response.body;
          _currentUrl = url;
        });
      } else {
        setState(() {
          _htmlContent = '重定向后请求失败，状态码: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _htmlContent = '重定向后请求出错: $e';
      });
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      setState(() {
        _htmlContent = '无法打开链接: $url';
      });
    }
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
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _fetchWebContent,
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
                    },
                    onLinkTap: (url, _, __) {
                      if (url != null) {
                        _launchUrl(url);
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
                  '当前URL: $_currentUrl',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
