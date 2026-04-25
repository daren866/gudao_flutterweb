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
  String _htmlContent = '<h2>欢迎使用简易浏览器</h2><p>请在上方输入网址并点击访问。</p>';
  bool _isLoading = false;
  String _currentUrl = '';

  // 统一请求逻辑，支持内部链接自动跳转
  Future<void> _fetchWebContent(String url) async {
    if (url.isEmpty) return;

    // 1. 处理相对路径 (拼接域名)
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      if (_currentUrl.isNotEmpty) {
        final uri = Uri.parse(_currentUrl);
        if (url.startsWith('/')) {
          url = '${uri.scheme}://${uri.host}$url';
        } else {
          url = '${uri.scheme}://${uri.host}/${uri.path.substring(0, uri.path.lastIndexOf('/'))}/$url';
        }
      } else {
        url = 'https://$url'; // 如果没域名，默认加 https
      }
    }

    setState(() {
      _isLoading = true;
      _currentUrl = url;
      _urlController.text = url; // 同步到输入框
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
          _htmlContent = '<div style="color: red;">请求失败，状态码: ${response.statusCode}</div>';
        });
      }
    } catch (e) {
      setState(() {
        _htmlContent = '<div style="color: red;">请求出错: $e</div>';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 专门用来处理 <input> 标签的 Flutter 组件生成
  Widget? _buildHtmlInput(element) {
    final type = element.attributes['type']?.toLowerCase() ?? 'text';
    final placeholder = element.attributes['placeholder'] ?? '';
    final value = element.attributes['value'] ?? '';
    final name = element.attributes['name'] ?? '';

    // 强制独占一行 (作为块级元素渲染)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: _InputWrapper(
        type: type,
        placeholder: placeholder,
        value: value,
        name: name,
      ),
    );
  }

  // 专门用来处理 <button> 标签的 Flutter 组件生成
  Widget? _buildHtmlButton(element) {
    final type = element.attributes['type']?.toLowerCase() ?? 'button';
    final text = element.innerHtml; // 获取 <button>内部的文字或图标

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: ElevatedButton(
        onPressed: () {
          if (type == 'submit') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('表单提交功能（模拟）被触发')),
            );
          } else if (type == 'reset') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('表单重置功能（模拟）被触发')),
            );
          } else {
            // 如果是普通 button
            print('Button clicked: $text');
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          side: const BorderSide(color: Colors.grey), // 模拟浏览器原生 button 样式
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
          // 顶部搜索栏
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: InputDecoration(
                      hintText: '输入网址',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.grey[200],
                    ),
                    onSubmitted: (value) => _fetchWebContent(value), // 支持键盘回车
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : () => _fetchWebContent(_urlController.text),
                  child: _isLoading 
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('访问'),
                ),
              ],
            ),
          ),

          // 加载进度条指示器
            child: LinearProgressIndicator(
              minHeight: 4,
              backgroundColor: Colors.transparent,
            ),
          ),

          // 底部网页渲染区域
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(width: 2, color: Theme.of(context).dividerColor),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: HtmlWidget(
                  _htmlContent,
                  // 拦截链接点击，在APP内部跳转
                  onTapUrl: (url) {
                    _fetchWebContent(url);
                    return true; // 返回 true 表示我们自己处理了跳转
                  },
                  // 自定义构建 <input> 控件
                  customWidgetBuilder: (element) {
                    if (element.localName == 'input') {
                      return _buildHtmlInput(element);
                    }
                    if (element.localName == 'button') {
                      return _buildHtmlButton(element);
                    }
                    return null; // 返回 null 表示交给插件自己处理其他标签
                  },
                  // 基础样式配置
                  textStyle: const TextStyle(fontSize: 16),
                  // 配置使其更像网页 (例如块级渲染，处理 margin 等)
                  customStylesBuilder: (element) {
                    return {
                      'margin': '0',
                      'padding': '0',
                    };
                  },
                ),
              ),
            ),
          ),

          // 底部状态栏显示当前真实 URL
          SafeArea(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

// ==========================================
// 自定义的 Input 控件包装器
// ==========================================
class _InputWrapper extends StatefulWidget {
  final String type;
  final String placeholder;
  final String value;
  final String name;

  const _InputWrapper({
    required this.type,
    required this.placeholder,
    required this.value,
    required this.name,
  });

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
    
    // 初始化 checkbox / radio 的状态
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
          obscureText: widget.type == 'password', // 如果是 password 类型则隐藏输入
          decoration: InputDecoration(
            hintText: widget.placeholder,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
          ),
        );
      
      case 'checkbox':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: _isChecked,
              onChanged: (val) => setState(() => _isChecked = val ?? false),
            ),
            Text(widget.placeholder.isNotEmpty ? widget.placeholder : widget.name),
          ],
        );
      
      case 'radio':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Radio<String>(
              value: widget.value.isNotEmpty ? widget.value : widget.name,
              groupValue: widget.value, // 基础模拟
              onChanged: (val) => setState(() {}),
            ),
            Text(widget.placeholder.isNotEmpty ? widget.placeholder : widget.name),
          ],
        );

      case 'submit':
      case 'button':
        return ElevatedButton(
          onPressed: () {
            // 点击 submit 按钮时的模拟动作
          },
          child: Text(widget.value.isNotEmpty ? widget.value : widget.type.toUpperCase()),
        );
        
      default:
        // 针对不支持的类型，返回一个基础的 text 输入框
        return TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: widget.placeholder,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
          ),
        );
    }
  }
}
