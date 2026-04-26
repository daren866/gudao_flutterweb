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
      home: const MyHomePage(title: '我的应用 (表单 + CSS布局兼容)'),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ======================================================================
// 轻量级 CSS 解析器（正则提取类名和样式属性）
// ======================================================================
class _SimpleCssParser {
  final Map<String, Map<String, String>> rules = {};

  void parse(String html) {
    final styleRegex = RegExp(r'<style[^>]*>(.*?)</style>', dotAll: true);
    final matches = styleRegex.allMatches(html);

    for (final match in matches) {
      final cssText = match.group(1)?.trim() ?? '';
      final cleanCss = cssText.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
      final blockRegex = RegExp(r'([^{]+)\{([^}]+)\}');
      final blocks = blockRegex.allMatches(cleanCss);

      for (final block in blocks) {
        final selector = block.group(1)?.trim() ?? '';
        final propertiesStr = block.group(2)?.trim() ?? '';
        final props = <String, String>{};
        final propRegex = RegExp(r'([\w-]+)\s*:\s*([^;]+);?');
        final propsMatches = propRegex.allMatches(propertiesStr);

        for (final prop in propsMatches) {
          final key = prop.group(1)?.trim().toLowerCase() ?? '';
          final value = prop.group(2)?.trim() ?? '';
          if (key.isNotEmpty) props[key] = value;
        }

        if (selector.startsWith('.') && props.isNotEmpty) {
          rules[selector] = props;
        }
      }
    }
  }

  Map<String, String>? getStylesForElement(dom.Element element) {
    final classes = element.classes;
    if (classes.isEmpty) return null;
    Map<String, String>? matchedStyles;
    for (final className in classes) {
      final selector = '.$className';
      if (rules.containsKey(selector)) {
        matchedStyles ??= {};
        matchedStyles.addAll(rules[selector]!);
      }
    }
    return matchedStyles;
  }
}

// ======================================================================
// 表单数据模型
// ======================================================================
class _FormData extends ChangeNotifier {
  final String method;
  final String action;
  final Map<String, String> values = {};

  _FormData({required this.method, required this.action});

  void setValue(String name, String value) {
    values[name] = value;
    notifyListeners();
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
  String _htmlContent = '''
    <style>
      .flex-row { display: flex; flex-direction: row; justify-content: space-between; gap: 10px; background-color: #f0f0f0; padding: 10px; margin-bottom: 15px; border-radius: 5px; }
      .flex-col { display: flex; flex-direction: column; gap: 8px; background-color: #e0f7fa; padding: 10px; margin-bottom: 15px; border-radius: 5px; }
      .grid-3 { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 10px; background-color: #fff3e0; padding: 10px; margin-bottom: 15px; border-radius: 5px; }
      .box { background-color: #2196f3; color: white; padding: 10px; border-radius: 4px; text-align: center; }
    </style>
    <h2>演示: CSS Style 兼容与表单</h2>
    <div class="flex-row"><div class="box">Flex 1</div><div class="box">Flex 2</div><div class="box">Flex 3</div></div>
    <div class="grid-3"><div class="box">G1</div><div class="box">G2</div><div class="box">G3</div></div>
    <form method="get" action="/search">
      <div class="flex-row">
        <input type="text" name="q" placeholder="输入关键词..." style="flex: 1;">
        <input type="submit" value="搜索">
      </div>
    </form>
  ''';
  
  bool _isLoading = false;
  String _currentUrl = '';
  final Map<int, _FormData> _formRegistry = {};
  late _SimpleCssParser cssParser;

  @override
  void initState() {
    super.initState();
    cssParser = _SimpleCssParser();
    _updateCssParser();
  }

  void _updateCssParser() {
    cssParser.parse(_htmlContent);
  }

  _FormData? _getFormDataForElement(dom.Element element) {
    dom.Node? node = element.parent;
    while (node != null) {
      if (node is dom.Element && node.localName == 'form') {
        final formElement = node;
        return _formRegistry.putIfAbsent(formElement.hashCode, () {
          final method = formElement.attributes['method']?.toLowerCase() ?? 'get';
          final action = formElement.attributes['action'] ?? '';
          return _FormData(method: method, action: action);
        });
      }
      node = node.parent;
    }
    return null;
  }

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

  String _fixEncoding(http.Response response) {
    final contentType = response.headers['content-type'] ?? '';
    if (contentType.toLowerCase().contains('charset=')) return response.body;
    final takeLen = response.bodyBytes.length > 1024 ? 1024 : response.bodyBytes.length;
    final previewBytes = response.bodyBytes.sublist(0, takeLen);
    final previewStr = utf8.decode(previewBytes, allowMalformed: true);
    final charsetRegex = RegExp(r'charset=([a-zA-Z0-9_-]+)', caseSensitive: false);
    final match = charsetRegex.firstMatch(previewStr);
    if (match != null && match.group(1)!.trim().toLowerCase().contains('utf')) {
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    }
    return response.body;
  }

  Future<void> _fetchWebContent(String url) async {
    if (url.isEmpty) return;
    final fullUrl = _resolveUrl(url);
    setState(() {
      _isLoading = true;
      _currentUrl = fullUrl;
      _urlController.text = fullUrl;
      _formRegistry.clear();
    });
    try {
      final response = await http.get(Uri.parse(fullUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      }).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        setState(() {
          _htmlContent = _fixEncoding(response);
          _updateCssParser(); // 网页加载后重新解析 CSS
        });
      } else {
        setState(() => _htmlContent = '<p style="color:red">请求失败: ${response.statusCode}</p>');
      }
    } catch (e) {
      setState(() => _htmlContent = '<p style="color:red">请求出错: $e</p>');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitForm(_FormData formData) async {
    final action = formData.action;
    final fullUrl = action.isNotEmpty ? _resolveUrl(action) : _currentUrl;
    if (fullUrl.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final data = Map.fromEntries(formData.values.entries.where((e) => e.key.isNotEmpty));
      http.Response response;
      if (formData.method == 'post') {
        response = await http.post(Uri.parse(fullUrl), headers: {
          'User-Agent': 'Mozilla/5.0...', 'Content-Type': 'application/x-www-form-urlencoded',
        }, body: data).timeout(const Duration(seconds: 10));
      } else {
        final queryString = data.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');
        final url = queryString.isNotEmpty ? '$fullUrl?$queryString' : fullUrl;
        response = await http.get(Uri.parse(url), headers: {
          'User-Agent': 'Mozilla/5.0...'
        }).timeout(const Duration(seconds: 10));
      }
      setState(() {
        _currentUrl = fullUrl; _urlController.text = fullUrl;
        if (response.statusCode == 200) {
          _htmlContent = _fixEncoding(response);
          _updateCssParser(); // 表单跳转后重新解析新页面的 CSS
        } else {
          _htmlContent = '<p style="color:red">提交返回状态码: ${response.statusCode}</p>';
        }
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('表单提交出错: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==================================================================
  // 核心：融合了 CSS 布局拦截 与 表单控件拦截
  // ==================================================================
  Widget? _buildCustomWidget(dom.Element element) {
    final tag = element.localName;
    
    // 1. 表单控件优先级最高（必须拦截，否则会变成纯文本）
    if (tag == 'input') return _buildHtmlInput(element);
    if (tag == 'button') return _buildHtmlButton(element);
    if (tag == 'select') return _buildHtmlSelect(element);
    if (tag == 'textarea') return _buildHtmlTextarea(element);
    if (tag == 'option') return const SizedBox.shrink();
    if (tag == 'style') return const SizedBox.shrink(); // 隐藏原本的style标签文本

    // 2. CSS Flex / Grid 布局拦截
    // 修复1：去掉 final，允许后续合并内联样式
    Map<String, String>? styles = cssParser.getStylesForElement(element);
    
    // 增加内联样式解析的回退
    final inlineStyle = element.attributes['style'];
    if (inlineStyle != null) {
      styles ??= {}; // 如果外部CSS没匹配到，初始化一个Map
      final propRegex = RegExp(r'([\w-]+)\s*:\s*([^;]+);?');
      propRegex.allMatches(inlineStyle).forEach((prop) {
        final key = prop.group(1)?.trim().toLowerCase() ?? '';
        final value = prop.group(2)?.trim() ?? '';
        if (key.isNotEmpty) styles![key] = value; // 内联样式覆盖外部样式
      });
    }

    // 修复2：使用 ?. 安全调用，并在不为空时才判断
    if (styles?['display'] == 'flex') return _buildFlexLayout(element, styles!);
    if (styles?['display'] == 'grid') return _buildGridLayout(element, styles!);

    return null; // 交给 flutter_widget_from_html 默认处理
  }

  // --------------------------------------------------
  // CSS 到 Flutter 布局翻译器
  // --------------------------------------------------
  Widget _buildFlexLayout(dom.Element element, Map<String, String> styles) {
    final direction = styles['flex-direction'] == 'column' ? Axis.vertical : Axis.horizontal;
    final mainAxisAlignment = _parseMainAxisAlignment(styles['justify-content']);
    final crossAxisAlignment = _parseCrossAxisAlignment(styles['align-items']);
    double? gap = _parsePx(styles['gap']);
    Color? bgColor = _parseColor(styles['background-color']);
    EdgeInsets padding = _parsePadding(styles['padding']);
    EdgeInsets margin = _parseMargin(styles['margin']);
    double? borderRadius = _parsePx(styles['border-radius']);

    final children = element.children.map((child) {
      return HtmlWidget(child.outerHtml, customWidgetBuilder: _buildCustomWidget);
    }).toList();

    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(borderRadius ?? 0)),
      child: Flex(
        direction: direction,
        mainAxisAlignment: mainAxisAlignment,
        crossAxisAlignment: crossAxisAlignment,
        children: _wrapWithGap(children, gap, direction),
      ),
    );
  }

  Widget _buildGridLayout(dom.Element element, Map<String, String> styles) {
    final columnsStr = styles['grid-template-columns'];
    int columnCount = columnsStr?.split(' ').where((s) => s.trim().isNotEmpty).length ?? 1;
    double? gap = _parsePx(styles['gap']);
    Color? bgColor = _parseColor(styles['background-color']);
    EdgeInsets padding = _parsePadding(styles['padding']);
    EdgeInsets margin = _parseMargin(styles['margin']);
    double? borderRadius = _parsePx(styles['border-radius']);

    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(borderRadius ?? 0)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalGap = gap != null ? (columnCount - 1) * gap : 0;
          final itemWidth = (constraints.maxWidth - padding.horizontal - totalGap) / columnCount;
          
          return Wrap(
            spacing: gap ?? 0,
            runSpacing: gap ?? 0,
            children: element.children.map((child) {
              return SizedBox(
                width: itemWidth,
                child: HtmlWidget(child.outerHtml, customWidgetBuilder: _buildCustomWidget),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  List<Widget> _wrapWithGap(List<Widget> children, double? gap, Axis direction) {
    if (gap == null || children.isEmpty) return children;
    return List.generate(children.length * 2 - 1, (index) {
      if (index.isOdd) {
        return SizedBox(width: direction == Axis.horizontal ? gap : 0, height: direction == Axis.vertical ? gap : 0);
      }
      return children[index ~/ 2];
    });
  }

  // --------------------------------------------------
  // 表单控件生成器 (与你原有代码完全一致)
  // --------------------------------------------------
  Widget? _buildHtmlInput(dom.Element element) {
    final type = element.attributes['type']?.toLowerCase() ?? 'text';
    final name = element.attributes['name'] ?? '';
    final value = element.attributes['value'] ?? '';
    final placeholder = element.attributes['placeholder'] ?? '';
    final formData = _getFormDataForElement(element);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: _InputWrapper(type: type, placeholder: placeholder, value: value, name: name, formData: formData, onSubmit: formData != null ? () => _submitForm(formData) : null),
    );
  }

  Widget? _buildHtmlButton(dom.Element element) {
    final type = element.attributes['type']?.toLowerCase() ?? 'button';
    final text = element.innerHtml;
    final formData = _getFormDataForElement(element);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: _FormButtonWrapper(type: type, text: text, formData: formData, onSubmit: formData != null ? () => _submitForm(formData) : null),
    );
  }

  Widget? _buildHtmlSelect(dom.Element element) {
    final name = element.attributes['name'] ?? '';
    final formData = _getFormDataForElement(element);
    final options = element.getElementsByTagName('option');
    final items = options.map((opt) => MapEntry(opt.text.trim(), opt.attributes['value'] ?? opt.text.trim())).toList();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4.0), child: _SelectWrapper(items: items, name: name, formData: formData));
  }

  Widget? _buildHtmlTextarea(dom.Element element) {
    final name = element.attributes['name'] ?? '';
    final placeholder = element.attributes['placeholder'] ?? '';
    final value = element.text.trim();
    final formData = _getFormDataForElement(element);
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4.0), child: _TextareaWrapper(name: name, placeholder: placeholder, value: value, formData: formData));
  }

  // --------------------------------------------------
  // CSS 属性解析辅助方法
  // --------------------------------------------------
  double? _parsePx(String? value) {
    if (value == null) return null;
    final match = RegExp(r'([\d.]+)').firstMatch(value);
    return match != null ? double.parse(match.group(1)!) : null;
  }
  Color? _parseColor(String? value) {
    if (value == null || !value.startsWith('#')) return null;
    final hex = value.replaceAll('#', '');
    if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
    return null;
  }
  EdgeInsets _parsePadding(String? value) => EdgeInsets.all(_parsePx(value) ?? 0);
  EdgeInsets _parseMargin(String? value) => EdgeInsets.all(_parsePx(value) ?? 0);
  MainAxisAlignment _parseMainAxisAlignment(String? value) {
    switch (value) {
      case 'center': return MainAxisAlignment.center;
      case 'space-between': return MainAxisAlignment.spaceBetween;
      case 'space-around': return MainAxisAlignment.spaceAround;
      case 'flex-end': return MainAxisAlignment.end;
      default: return MainAxisAlignment.start;
    }
  }
  CrossAxisAlignment _parseCrossAxisAlignment(String? value) {
    switch (value) {
      case 'center': return CrossAxisAlignment.center;
      case 'flex-end': return CrossAxisAlignment.end;
      case 'stretch': return CrossAxisAlignment.stretch;
      default: return CrossAxisAlignment.center;
    }
  }

  // ==================================================================
  // UI 主框架
  // ==================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), backgroundColor: Theme.of(context).colorScheme.inversePrimary),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _urlController, onSubmitted: _fetchWebContent, decoration: InputDecoration(hintText: '输入网址', border: const OutlineInputBorder(), filled: true, fillColor: Colors.grey[200]))),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : () => _fetchWebContent(_urlController.text),
                  child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('访问'),
                ),
              ],
            ),
          ),
          if (_isLoading) const Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: LinearProgressIndicator(minHeight: 4, backgroundColor: Colors.transparent)),
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: Border.all(width: 2, color: Theme.of(context).dividerColor)),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: HtmlWidget(
                  _htmlContent,
                  onTapUrl: (url) { _fetchWebContent(url); return true; },
                  customWidgetBuilder: _buildCustomWidget, // 统一入口
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
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// 底部表单组件区（完全保留你原来的逻辑，解决 const 警告）
// ======================================================================
class _InputWrapper extends StatefulWidget {
  final String type;
  final String placeholder;
  final String value;
  final String name;
  final _FormData? formData;
  final VoidCallback? onSubmit;
  const _InputWrapper({required this.type, required this.placeholder, required this.value, required this.name, this.formData, this.onSubmit});
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
    if (widget.formData != null && widget.name.isNotEmpty) {
      if (widget.type == 'checkbox') { _isChecked = widget.value.isNotEmpty || widget.value == 'true'; widget.formData!.setValue(widget.name, _isChecked ? widget.value : ''); }
      else if (widget.type == 'radio') { _isChecked = widget.formData!.values[widget.name] == widget.value; }
      else { widget.formData!.values[widget.name] = widget.value; }
    }
    _controller.addListener(_onTextChanged);
    widget.formData?.addListener(_onFormChanged);
  }
  void _onTextChanged() {
    if (widget.formData != null && widget.name.isNotEmpty && !['checkbox', 'radio', 'submit', 'reset', 'button', 'hidden'].contains(widget.type)) {
      widget.formData!.values[widget.name] = _controller.text;
    }
  }
  void _onFormChanged() { if (widget.type == 'radio' && widget.formData != null && mounted) setState(() => _isChecked = widget.formData!.values[widget.name] == widget.value); }
  @override
  void dispose() { _controller.removeListener(_onTextChanged); _controller.dispose(); widget.formData?.removeListener(_onFormChanged); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    switch (widget.type) {
      case 'text': case 'search': case 'email': case 'password': case 'url': case 'tel': case 'number': case 'date':
        return TextField(controller: _controller, obscureText: widget.type == 'password', decoration: InputDecoration(hintText: widget.placeholder, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(4))));
      case 'hidden': return const SizedBox.shrink();
      case 'checkbox':
        return Row(mainAxisSize: MainAxisSize.min, children: [ Checkbox(value: _isChecked, onChanged: (val) { setState(() => _isChecked = val ?? false); if (widget.formData != null && widget.name.isNotEmpty) widget.formData!.setValue(widget.name, _isChecked ? widget.value : ''); }), Text(widget.placeholder.isNotEmpty ? widget.placeholder : widget.name), ]);
      case 'radio':
        return GestureDetector(onTap: () { if (widget.formData != null && widget.name.isNotEmpty) widget.formData!.setValue(widget.name, widget.value); }, child: Padding(padding: const EdgeInsets.only(bottom: 4.0), child: Row(mainAxisSize: MainAxisSize.min, children: [ Container(width: 20, height: 20, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _isChecked ? Colors.blue : Colors.grey, width: 2)), child: _isChecked ? Center(child: Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.blue))) : null), const SizedBox(width: 8), Text(widget.placeholder.isNotEmpty ? widget.placeholder : widget.value), ])));
      case 'submit':
        return ElevatedButton(onPressed: widget.onSubmit, style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white), child: Text(widget.value.isNotEmpty ? widget.value : 'Submit'));
      case 'reset':
        return ElevatedButton(onPressed: () { widget.formData?.values.clear(); _controller.clear(); setState(() => _isChecked = false); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, foregroundColor: Colors.white), child: Text(widget.value.isNotEmpty ? widget.value : 'Reset'));
      case 'button': default:
        return ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black87, side: const BorderSide(color: Colors.grey)), child: Text(widget.value.isNotEmpty ? widget.value : (widget.type.toUpperCase())));
    }
  }
}

class _FormButtonWrapper extends StatelessWidget {
  final String type; final String text; final _FormData? formData; final VoidCallback? onSubmit;
  const _FormButtonWrapper({required this.type, required this.text, this.formData, this.onSubmit});
  @override
  Widget build(BuildContext context) {
    if (type == 'submit') return ElevatedButton(onPressed: onSubmit, style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white), child: Text(text.isEmpty ? 'Submit' : text));
    if (type == 'reset') return ElevatedButton(onPressed: () => formData?.values.clear(), style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, foregroundColor: Colors.white), child: Text(text.isEmpty ? 'Reset' : text));
    return ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black87, side: const BorderSide(color: Colors.grey)), child: Text(text.isEmpty ? 'Button' : text));
  }
}

class _SelectWrapper extends StatefulWidget {
  final List<MapEntry<String, String>> items; final String name; final _FormData? formData;
  const _SelectWrapper({required this.items, required this.name, this.formData});
  @override State<_SelectWrapper> createState() => _SelectWrapperState();
}
class _SelectWrapperState extends State<_SelectWrapper> {
  String? _selectedValue;
  @override void initState() { super.initState(); if (widget.items.isNotEmpty) _selectedValue = widget.items.first.value; if (widget.formData != null && widget.name.isNotEmpty) widget.formData!.values[widget.name] = _selectedValue ?? ''; }
  @override Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: widget.items.any((e) => e.value == _selectedValue) ? _selectedValue : null,
      decoration: InputDecoration(border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
      items: widget.items.map((item) => DropdownMenuItem<String>(value: item.value, child: Text(item.key))).toList(),
      onChanged: (val) { setState(() => _selectedValue = val); if (widget.formData != null && widget.name.isNotEmpty) widget.formData!.values[widget.name] = val ?? ''; },
    );
  }
}

class _TextareaWrapper extends StatefulWidget {
  final String name; final String placeholder; final String value; final _FormData? formData;
  const _TextareaWrapper({required this.name, required this.placeholder, required this.value, this.formData});
  @override State<_TextareaWrapper> createState() => _TextareaWrapperState();
}
class _TextareaWrapperState extends State<_TextareaWrapper> {
  late TextEditingController _controller;
  @override void initState() { super.initState(); _controller = TextEditingController(text: widget.value); if (widget.formData != null && widget.name.isNotEmpty) widget.formData!.values[widget.name] = widget.value; _controller.addListener(() { if (widget.formData != null && widget.name.isNotEmpty) widget.formData!.values[widget.name] = _controller.text; }); }
  @override void dispose() { _controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => TextField(controller: _controller, maxLines: 4, decoration: InputDecoration(hintText: widget.placeholder, border: const OutlineInputBorder()));
}
