import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

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
        useMaterial3: true,
      ),
      home: const MyHomePage(title: '我的应用 (完美防乱码)'),
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
  String _htmlContent =
      '<h2>欢迎使用简易浏览器</h2><p>支持 HTTP/HTTPS，完美解决中文乱码问题。</p>';
  bool _isLoading = false;
  String _currentUrl = '';

  // ==================== 核心防乱码方法 ====================
  String _fixEncoding(http.Response response) {
    final contentType = response.headers['content-type'] ?? '';

    // 1. 如果响应头已经明确声明了字符集，直接用默认的 body 即可
    if (contentType.toLowerCase().contains('charset=')) {
      return response.body;
    }

    // 2. 响应头没有字符集时，手动读取前 1024 字节去嗅探 HTML meta 标签
    int takeLen = response.bodyBytes.length > 1024 ? 1024 : response.bodyBytes.length;
    List<int> previewBytes = response.bodyBytes.sublist(0, takeLen);

    // 用 UTF-8 粗略解码（允许部分字节错误）
    String previewStr = utf8.decode(previewBytes, allowMalformed: true);

    // 查找 <meta charset="xxx"> 或 <meta http-equiv="Content-Type" content="...; charset=xxx">
    // 用变量单独存储正则字符串，防止 Markdown 转义吞掉反斜杠
    String charsetPattern = r'charset=["\' ]?([^"\' ;>]+)';
    RegExp charsetRegex = RegExp(charsetPattern, caseSensitive: false);
    Match? match = charsetRegex.firstMatch(previewStr);

    if (match != null) {
      String foundCharset = match.group(1)!.trim().toLowerCase();
      if (foundCharset.contains('utf') || foundCharset == 'utf8') {
        // 找到 UTF-8 声明，强制用 UTF-8 解码整个网页字节流
        return utf8.decode(response.bodyBytes, allowMalformed: true);
      }
    }

    // 3. 兜底：什么都没找到，按 GBK（简体中文网页常见）尝试解码
    try {
      return gbk.decode(response.bodyBytes);
    } catch (_) {
      // GBK 也失败了，只能返回默认的（可能乱码）
      return response.body;
    }
  }
  // ==================== 核心防乱码方法结束 ====================

  Future<void> _fetchWebContent(String url) async {
    if (url.isEmpty) return;

    // 处理相对路径
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      if (_currentUrl.isNotEmpty) {
        final uri = Uri.parse(_currentUrl);
        if (url.startsWith('/')) {
          url = '${uri.scheme}://${uri.host}$url';
        } else {
          String path = uri.path;
          int lastSlash = path.lastIndexOf('/');
          String basePath = lastSlash > 0 ? path.substring(0, lastSlash) : '';
          url = '${uri.scheme}://${uri.host}$basePath/$url';
        }
      } else {
        url = 'https://$url';
      }
    }

    setState(() {
      _isLoading = true;
      _currentUrl = url;
      _urlController.text = url;
    });

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
          'Accept-Charset': 'utf-8',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        String decodedHtml = _fixEncoding(response);
        setState(() {
          _htmlContent = decodedHtml;
        });
      } else {
        setState(() {
          _htmlContent =
              '<div style="color: red;">请求失败，状态码: ${response.statusCode}</div>';
        });
      }
    } catch (e) {
      setState(() {
        _htmlContent = '<div style="color: red;">请求出错: $e</div>';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget? _buildHtmlInput(element) {
    final type = element.attributes['type']?.toLowerCase() ?? 'text';
    final placeholder = element.attributes['placeholder'] ?? '';
    final value = element.attributes['value'] ?? '';
    final name = element.attributes['name'] ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: _InputWrapper(
          type: type, placeholder: placeholder, value: value, name: name),
    );
  }

  Widget? _buildHtmlButton(element) {
    final type = element.attributes['type']?.toLowerCase() ?? 'button';
    final text = element.innerHtml;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: ElevatedButton(
        onPressed: () {
          if (type == 'submit') {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('表单提交（模拟）')));
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          side: const BorderSide(color: Colors.grey),
        ),
        child: Text(text.isEmpty ? 'Button' : text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: InputDecoration(
                      hintText: '输入网址 (试试 http://www.baidu.com)',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.grey[200],
                    ),
                    onSubmitted: (value) => _fetchWebContent(value),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () => _fetchWebContent(_urlController.text),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('访问'),
                ),
              ],
            ),
          ),

          // 加载进度条
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: LinearProgressIndicator(
                  minHeight: 4, backgroundColor: Colors.transparent),
            ),

          // 网页渲染区域
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border:
                    Border.all(width: 2, color: Theme.of(context).dividerColor),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: HtmlWidget(
                  _htmlContent,
                  onTapUrl: (url) {
                    _fetchWebContent(url);
                    return true;
                  },
                  customWidgetBuilder: (element) {
                    if (element.localName == 'input') {
                      return _buildHtmlInput(element);
                    }
                    if (element.localName == 'button') {
                      return _buildHtmlButton(element);
                    }
                    return null;
                  },
                  textStyle: const TextStyle(fontSize: 16),
                  customStylesBuilder: (element) {
                    return {'margin': '0', 'padding': '0'};
                  },
                ),
              ),
            ),
          ),

          // 底部状态栏
          SafeArea(
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[300],
              child: Text(
                '当前 URL: $_currentUrl',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
        ],
      ),
    );
  }
}

// ==================== Input 控件包装器 ====================
class _InputWrapper extends StatefulWidget {
  final String type;
  final String placeholder;
  final String value;
  final String name;

  const _InputWrapper(
      {required this.type,
      required this.placeholder,
      required this.value,
      required this.name});

  @override
  State<_InputWrapper> createState() => _InputWrapperState();
}

class _InputWrapperState extends State<_InputWrapper> {
  late TextEditingController _controller;
  bool _isChecked = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    if (widget.type == 'checkbox') {
      _isChecked = widget.value.isNotEmpty;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.type) {
      case 'text':
      case 'search':
      case 'email':
      case 'password':
      case 'url':
        return TextField(
          controller: _controller,
          obscureText: widget.type == 'password',
          decoration: InputDecoration(
            hintText: widget.placeholder,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
          ),
        );
      case 'checkbox':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
                value: _isChecked,
                onChanged: (val) => setState(() => _isChecked = val ?? false)),
            Text(widget.placeholder.isNotEmpty ? widget.placeholder : widget.name),
          ],
        );
      case 'radio':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: ChoiceChip(
            label: Text(
                widget.placeholder.isNotEmpty ? widget.placeholder : widget.name),
            selected: _isChecked,
            onSelected: (selected) => setState(() => _isChecked = selected),
          ),
        );
      case 'submit':
      case 'button':
        return ElevatedButton(
          onPressed: () {},
          child: Text(widget.value.isNotEmpty
              ? widget.value
              : widget.type.toUpperCase()),
        );
      default:
        return TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: widget.placeholder,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
          ),
        );
    }
  }
}
