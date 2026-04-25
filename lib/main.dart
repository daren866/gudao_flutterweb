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
  String _htmlContent = '<h2>欢迎使用简易浏览器</h2><p>支持 HTTP/HTTPS，完美解决中文乱码问题。</p>';
  bool _isLoading = false;
  String _currentUrl = '';

  Future<void> _fetchWebContent(String url) async {
    if (url.isEmpty) return;

    // 处理相对路径
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      if (_currentUrl.isNotEmpty) {
        final uri = Uri.parse(_currentUrl);
        if (url.startsWith('/')) {
          url = '${uri.scheme}://${uri.host}$url';
        } else {
          url = '${uri.scheme}://${uri.host}/${uri.path.substring(0, uri.path.lastIndexOf('/'))}/$url';
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
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
          'Accept-Charset': 'utf-8', // 尝试告诉服务器我们要 UTF-8
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // ================= 核心防乱码逻辑 =================
        String decodedHtml;
        
        // 1. 检查 HTTP 响应头是否明确包含了 charset
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.contains('charset=')) {
          // 如果头部有，直接用 body，http 包已经处理好了
          decodedHtml = response.body;
        } else {
          // 2. 如果头部没有（通常是纯 HTTP 站点如 http://www.baidu.com）
          // 我们先取前 1024 个字节，只解码这部分去寻找 <meta charset> 标签
          final previewBytes = response.bodyBytes.sublist(0, response.bodyBytes.length > 1024 ? 1024 : response.bodyBytes.length);
          final previewStr = utf8.decode(previewBytes, allowMalformed: true);
          
          // 用正则匹配 <meta charset="xxx"> 或 <meta http-equiv="Content-Type" content="text/html; charset=xxx">
          final charsetRegex = RegExp(r'charset=["\']?([^"\';\s>]+)', caseSensitive: false);
          final match = charsetRegex.firstMatch(previewStr);
          
          if (match != null && match.group(1)!.toLowerCase() == 'utf-8') {
            // 如果 HTML 代码里声明了是 UTF-8，我们就强制用 UTF-8 解码整个字节流！
            decodedHtml = utf8.decode(response.bodyBytes);
          } else {
            // 如果也没找到 meta 标签，退回使用默认的 body（虽然可能乱码，但这是最后防线）
            decodedHtml = response.body;
          }
        }
        // ================= 核心防乱码逻辑结束 =================

        setState(() {
          _htmlContent = decodedHtml;
        });
      } else {
        setState(() {
          _htmlContent = '<div style="color: red;">请求失败，状态码: ${response.statusCode}</div>';
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

  // 处理 <input> 标签
  Widget? _buildHtmlInput(element) {
    final type = element.attributes['type']?.toLowerCase() ?? 'text';
    final placeholder = element.attributes['placeholder'] ?? '';
    final value = element.attributes['value'] ?? '';
    final name = element.attributes['name'] ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: _InputWrapper(type: type, placeholder: placeholder, value: value, name: name),
    );
  }

  // 处理 <button> 标签
  Widget? _buildHtmlButton(element) {
    final type = element.attributes['type']?.toLowerCase() ?? 'button';
    final text = element.innerHtml;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: ElevatedButton(
        onPressed: () {
          if (type == 'submit') {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('表单提交（模拟）')));
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
                  onPressed: _isLoading ? null : () => _fetchWebContent(_urlController.text),
                  child: _isLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('访问'),
                ),
              ],
            ),
          ),
          
          if (_isLoading) 
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: LinearProgressIndicator(minHeight: 4, backgroundColor: Colors.transparent),
            ),

          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(width: 2, color: Theme.of(context).dividerColor),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: HtmlWidget(
                  _htmlContent,
                  onTapUrl: (url) {
                    _fetchWebContent(url); // 内部跳转
                    return true;
                  },
                  customWidgetBuilder: (element) {
                    if (element.localName == 'input') return _buildHtmlInput(element);
                    if (element.localName == 'button') return _buildHtmlButton(element);
                    return null;
                  },
                  textStyle: const TextStyle(fontSize: 16),
                  customStylesBuilder: (element) => {'margin': '0', 'padding': '0'},
                ),
              ),
            ),
          ),
          SafeArea(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[300],
              child: Text('当前 URL: $_currentUrl', style: const TextStyle(fontSize: 12, color: Colors.black54), overflow: TextOverflow.ellipsis),
            ),
          )
        ],
      ),
    );
  }
}

// Input 控件包装器
class _InputWrapper extends StatefulWidget {
  final String type;
  final String placeholder;
  final String value;
  final String name;

  const _InputWrapper({required this.type, required this.placeholder, required this.value, required this.name});

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
    if (widget.type == 'checkbox') _isChecked = widget.value.isNotEmpty;
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
          ),
        );
      case 'checkbox':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Checkbox(value: _isChecked, onChanged: (val) => setState(() => _isChecked = val ?? false)),
          Text(widget.placeholder.isNotEmpty ? widget.placeholder : widget.name),
        ]);
      case 'radio':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: ChoiceChip(
            label: Text(widget.placeholder.isNotEmpty ? widget.placeholder : widget.name),
            selected: _isChecked,
            onSelected: (selected) => setState(() => _isChecked = selected),
          ),
        );
      case 'submit':
      case 'button':
        return ElevatedButton(onPressed: () {}, child: Text(widget.value.isNotEmpty ? widget.value : widget.type.toUpperCase()));
      default:
        return TextField(controller: _controller, decoration: InputDecoration(hintText: widget.placeholder, border: OutlineInputBorder(borderRadius: BorderRadius.circular(4))));
    }
  }
}
