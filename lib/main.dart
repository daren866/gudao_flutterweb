import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '我的应用',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const MyHomePage(title: '我的应用 (完整表单提交)'),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ======================================================================
// 表单数据模型 —— 继承 ChangeNotifier 实现跨控件联动（Radio 互斥等）
// ======================================================================
class _FormData extends ChangeNotifier {
  final String method; // get 或 post
  final String action; // 提交目标地址
  final Map<String, String> values = {}; // 所有带 name 的输入值

  _FormData({required this.method, required this.action});

  void setValue(String name, String value) {
    values[name] = value;
    notifyListeners(); // 通知同 form 下所有监听者（如 Radio 互斥）
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
  String _htmlContent = '<h2>欢迎使用</h2><p>完整支持 form 提交、input / button / select / textarea。</p>';
  bool _isLoading = false;
  String _currentUrl = '';

  // 表单注册表：key = <form> DOM 节点的 hashCode
  final Map<int, _FormData> _formRegistry = {};

  // ------------------------------------------------------------------
  // 向上遍历 DOM 树，找到所属 <form>，没有则自动注册
  // ------------------------------------------------------------------
  _FormData? _getFormDataForElement(dom.Element element) {
    dom.Node? node = element.parent;
    while (node != null) {
      if (node is dom.Element && node.localName == 'form') {
        return _formRegistry.putIfAbsent(node.hashCode, () {
          final method = node.attributes['method']?.toLowerCase() ?? 'get';
          final action = node.attributes['action'] ?? '';
          return _FormData(method: method, action: action);
        });
      }
      node = node.parent;
    }
    return null;
  }

  // ------------------------------------------------------------------
  // 相对路径 → 绝对路径
  // ------------------------------------------------------------------
  String _resolveUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (_currentUrl.isEmpty) return 'https://$url';
    final uri = Uri.parse(_currentUrl);
    if (url.startsWith('/')) return '${uri.scheme}://${uri.host}$url';
    final path = uri.path;
    final lastSlash = path.lastIndexOf('/');
    final basePath = lastSlash > 0 ? path.substring(0, lastSlash) : '';
    return '${uri.scheme}://${uri.host}$basePath/$url';
  }

  // ------------------------------------------------------------------
  // 防乱码
  // ------------------------------------------------------------------
  String _fixEncoding(http.Response response) {
    final contentType = response.headers['content-type'] ?? '';
    if (contentType.toLowerCase().contains('charset=')) return response.body;
    final takeLen =
        response.bodyBytes.length > 1024 ? 1024 : response.bodyBytes.length;
    final previewBytes = response.bodyBytes.sublist(0, takeLen);
    final previewStr = utf8.decode(previewBytes, allowMalformed: true);
    final charsetRegex =
        RegExp(r'charset=([a-zA-Z0-9_-]+)', caseSensitive: false);
    final match = charsetRegex.firstMatch(previewStr);
    if (match != null &&
        match.group(1)!.trim().toLowerCase().contains('utf')) {
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    }
    return response.body;
  }

  // ------------------------------------------------------------------
  // 加载网页
  // ------------------------------------------------------------------
  Future<void> _fetchWebContent(String url) async {
    if (url.isEmpty) return;
    final fullUrl = _resolveUrl(url);

    setState(() {
      _isLoading = true;
      _currentUrl = fullUrl;
      _urlController.text = fullUrl;
      _formRegistry.clear(); // 切换页面时清理旧表单
    });

    try {
      final response = await http
          .get(Uri.parse(fullUrl), headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        setState(() => _htmlContent = _fixEncoding(response));
      } else {
        setState(
            () => _htmlContent = '<p style="color:red">请求失败: ${response.statusCode}</p>');
      }
    } catch (e) {
      setState(() => _htmlContent = '<p style="color:red">请求出错: $e</p>');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==================================================================
  // 表单提交核心逻辑（完全模拟浏览器 5 步流程）
  // ==================================================================
  Future<void> _submitForm(_FormData formData) async {
    final action = formData.action;
    final fullUrl =
        action.isNotEmpty ? _resolveUrl(action) : _currentUrl;
    if (fullUrl.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      // 第 1 步：收集表单里所有带 name 的输入值（已实时同步在 formData.values 中）
      // 第 2 步：过滤掉空 name 的条目
      final data = Map.fromEntries(
        formData.values.entries.where((e) => e.key.isNotEmpty),
      );

      http.Response response;

      if (formData.method == 'post') {
        // 第 3 步 (POST)：数据放在请求体
        response = await http
            .post(Uri.parse(fullUrl), headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Content-Type': 'application/x-www-form-urlencoded',
        }, body: data)
            .timeout(const Duration(seconds: 10));
      } else {
        // 第 3 步 (GET)：数据拼成查询字符串
        final queryString = data.entries
            .map((e) =>
                '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
            .join('&');
        final url =
            queryString.isNotEmpty ? '$fullUrl?$queryString' : fullUrl;
        // 第 4 步：发起 GET 请求
        response = await http
            .get(Uri.parse(url), headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        }).timeout(const Duration(seconds: 10));
      }

      // 第 5 步：渲染服务器响应
      setState(() {
        _currentUrl = fullUrl;
        _urlController.text = fullUrl;
        if (response.statusCode == 200) {
          _htmlContent = _fixEncoding(response);
        } else {
          _htmlContent =
              '<p style="color:red">提交返回状态码: ${response.statusCode}</p>';
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('表单提交出错: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==================================================================
  // HTML 标签 → Flutter 控件 构建器
  // ==================================================================

  Widget? _buildHtmlInput(dom.Element element) {
    final type = element.attributes['type']?.toLowerCase() ?? 'text';
    final name = element.attributes['name'] ?? '';
    final value = element.attributes['value'] ?? '';
    final placeholder = element.attributes['placeholder'] ?? '';
    final formData = _getFormDataForElement(element);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: _InputWrapper(
        type: type,
        placeholder: placeholder,
        value: value,
        name: name,
        formData: formData,
        onSubmit: formData != null ? () => _submitForm(formData) : null,
      ),
    );
  }

  Widget? _buildHtmlButton(dom.Element element) {
    final type = element.attributes['type']?.toLowerCase() ?? 'button';
    final text = element.innerHtml;
    final formData = _getFormDataForElement(element);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: _FormButtonWrapper(
        type: type,
        text: text,
        formData: formData,
        onSubmit: formData != null ? () => _submitForm(formData) : null,
      ),
    );
  }

  Widget? _buildHtmlSelect(dom.Element element) {
    final name = element.attributes['name'] ?? '';
    final formData = _getFormDataForElement(element);

    final options = element.getElementsByTagName('option');
    final items = options.map((opt) {
      final label = opt.text.trim();
      final val = opt.attributes['value'] ?? label;
      return MapEntry(label, val);
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: _SelectWrapper(items: items, name: name, formData: formData),
    );
  }

  Widget? _buildHtmlTextarea(dom.Element element) {
    final name = element.attributes['name'] ?? '';
    final placeholder = element.attributes['placeholder'] ?? '';
    final value = element.text.trim();
    final formData = _getFormDataForElement(element);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: _TextareaWrapper(
          name: name, placeholder: placeholder, value: value, formData: formData),
    );
  }

  // ==================================================================
  // UI 主框架
  // ==================================================================
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
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    onSubmitted: _fetchWebContent,
                    decoration: InputDecoration(
                      hintText: '输入网址',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.grey[200],
                    ),
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

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: LinearProgressIndicator(
                  minHeight: 4, backgroundColor: Colors.transparent),
            ),

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
                    final tag = element.localName;
                    if (tag == 'input') return _buildHtmlInput(element);
                    if (tag == 'button') return _buildHtmlButton(element);
                    if (tag == 'select') return _buildHtmlSelect(element);
                    if (tag == 'textarea') return _buildHtmlTextarea(element);
                    if (tag == 'option') return const SizedBox.shrink();
                    return null;
                  },
                  textStyle: const TextStyle(fontSize: 16),
                  customStylesBuilder: (element) =>
                      {'margin': '0', 'padding': '0'},
                ),
              ),
            ),
          ),

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
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// Input 控件 —— 支持 text / password / checkbox / radio / submit / reset
// ======================================================================
class _InputWrapper extends StatefulWidget {
  final String type;
  final String placeholder;
  final String value;
  final String name;
  final _FormData? formData;
  final VoidCallback? onSubmit;

  const _InputWrapper({
    required this.type,
    required this.placeholder,
    required this.value,
    required this.name,
    this.formData,
    this.onSubmit,
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

    // 把初始值注册到所属 form
    if (widget.formData != null && widget.name.isNotEmpty) {
      if (widget.type == 'checkbox') {
        _isChecked = widget.value.isNotEmpty || widget.value == 'true';
        widget.formData!.setValue(widget.name, _isChecked ? widget.value : '');
      } else if (widget.type == 'radio') {
        _isChecked = widget.formData!.values[widget.name] == widget.value;
      } else {
        widget.formData!.values[widget.name] = widget.value;
      }
    }

    // 文本变化时实时同步到 form
    _controller.addListener(_onTextChanged);

    // 监听 form 变化（Radio 互斥的核心：A 选中 → formData 通知 B 取消）
    widget.formData?.addListener(_onFormChanged);
  }

  void _onTextChanged() {
    if (widget.formData != null &&
        widget.name.isNotEmpty &&
        widget.type != 'checkbox' &&
        widget.type != 'radio' &&
        widget.type != 'submit' &&
        widget.type != 'reset' &&
        widget.type != 'button' &&
        widget.type != 'hidden') {
      widget.formData!.values[widget.name] = _controller.text;
    }
  }

  // form 数据变化时回调（Radio 互斥）
  void _onFormChanged() {
    if (widget.type == 'radio' && widget.formData != null && mounted) {
      setState(() {
        _isChecked = widget.formData!.values[widget.name] == widget.value;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    widget.formData?.removeListener(_onFormChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.type) {
      // ---------- 文本类 ----------
      case 'text':
      case 'search':
      case 'email':
      case 'password':
      case 'url':
      case 'tel':
      case 'number':
      case 'date':
        return TextField(
          controller: _controller,
          obscureText: widget.type == 'password',
          keyboardType: widget.type == 'email'
              ? TextInputType.emailAddress
              : widget.type == 'url'
                  ? TextInputType.url
                  : widget.type == 'tel'
                      ? TextInputType.phone
                      : widget.type == 'number'
                          ? TextInputType.number
                          : TextInputType.text,
          decoration: InputDecoration(
            hintText: widget.placeholder,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
          ),
        );

      // ---------- 隐藏域 ----------
      case 'hidden':
        return const SizedBox.shrink();

      // ---------- 复选框 ----------
      case 'checkbox':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: _isChecked,
              onChanged: (val) {
                setState(() => _isChecked = val ?? false);
                if (widget.formData != null && widget.name.isNotEmpty) {
                  widget.formData!.setValue(
                      widget.name, _isChecked ? widget.value : '');
                }
              },
            ),
            Text(widget.placeholder.isNotEmpty
                ? widget.placeholder
                : widget.name),
          ],
        );

      // ---------- 单选框（手绘，避免废弃 API） ----------
      case 'radio':
        return GestureDetector(
          onTap: () {
            if (widget.formData != null && widget.name.isNotEmpty) {
              widget.formData!.setValue(widget.name, widget.value);
            }
          },
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _isChecked ? Colors.blue : Colors.grey,
                        width: 2),
                  ),
                  child: _isChecked
                      ? Center(
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blue,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Text(widget.placeholder.isNotEmpty
                    ? widget.placeholder
                    : widget.value),
              ],
            ),
          ),
        );

      // ---------- 提交按钮 ----------
      case 'submit':
        return ElevatedButton(
          onPressed: widget.onSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
          ),
          child: Text(
              widget.value.isNotEmpty ? widget.value : 'Submit'),
        );

      // ---------- 重置按钮 ----------
      case 'reset':
        return ElevatedButton(
          onPressed: () {
            widget.formData?.values.clear();
            _controller.clear();
            setState(() => _isChecked = false);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey,
            foregroundColor: Colors.white,
          ),
          child: Text(
              widget.value.isNotEmpty ? widget.value : 'Reset'),
        );

      // ---------- 普通按钮 ----------
      case 'button':
      default:
        return ElevatedButton(
          onPressed: () {},
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            side: const BorderSide(color: Colors.grey),
          ),
          child: Text(widget.value.isNotEmpty
              ? widget.value
              : (widget.type.toUpperCase())),
        );
    }
  }
}

// ======================================================================
// Button 控件 —— 支持 submit / reset / button
// ======================================================================
class _FormButtonWrapper extends StatelessWidget {
  final String type;
  final String text;
  final _FormData? formData;
  final VoidCallback? onSubmit;

  const _FormButtonWrapper({
    required this.type,
    required this.text,
    this.formData,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    if (type == 'submit') {
      return ElevatedButton(
        onPressed: onSubmit,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
        ),
        child: Text(text.isEmpty ? 'Submit' : text),
      );
    }
    if (type == 'reset') {
      return ElevatedButton(
        onPressed: () => formData?.values.clear(),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey,
          foregroundColor: Colors.white,
        ),
        child: Text(text.isEmpty ? 'Reset' : text),
      );
    }
    return ElevatedButton(
      onPressed: () {},
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        side: const BorderSide(color: Colors.grey),
      ),
      child: Text(text.isEmpty ? 'Button' : text),
    );
  }
}

// ======================================================================
// Select 控件 —— <select><option>...</option></select>
// ======================================================================
class _SelectWrapper extends StatefulWidget {
  final List<MapEntry<String, String>> items;
  final String name;
  final _FormData? formData;

  const _SelectWrapper({
    required this.items,
    required this.name,
    this.formData,
  });

  @override
  State<_SelectWrapper> createState() => _SelectWrapperState();
}

class _SelectWrapperState extends State<_SelectWrapper> {
  String? _selectedValue;

  @override
  void initState() {
    super.initState();
    if (widget.items.isNotEmpty) {
      _selectedValue = widget.items.first.value;
    }
    if (widget.formData != null && widget.name.isNotEmpty) {
      widget.formData!.values[widget.name] = _selectedValue ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value:
          widget.items.any((e) => e.value == _selectedValue) ? _selectedValue : null,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      items: widget.items.map((item) {
        return DropdownMenuItem<String>(
          value: item.value,
          child: Text(item.key),
        );
      }).toList(),
      onChanged: (val) {
        setState(() => _selectedValue = val);
        if (widget.formData != null && widget.name.isNotEmpty) {
          widget.formData!.values[widget.name] = val ?? '';
        }
      },
    );
  }
}

// ======================================================================
// Textarea 控件
// ======================================================================
class _TextareaWrapper extends StatefulWidget {
  final String name;
  final String placeholder;
  final String value;
  final _FormData? formData;

  const _TextareaWrapper({
    required this.name,
    required this.placeholder,
    required this.value,
    this.formData,
  });

  @override
  State<_TextareaWrapper> createState() => _TextareaWrapperState();
}

class _TextareaWrapperState extends State<_TextareaWrapper> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    if (widget.formData != null && widget.name.isNotEmpty) {
      widget.formData!.values[widget.name] = widget.value;
    }
    _controller.addListener(() {
      if (widget.formData != null && widget.name.isNotEmpty) {
        widget.formData!.values[widget.name] = _controller.text;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLines: 4,
      decoration: InputDecoration(
        hintText: widget.placeholder,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
