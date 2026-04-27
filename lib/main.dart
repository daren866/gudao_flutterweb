import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:flutter_js/flutter_js.dart';

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
      home: const MyHomePage(title: '我的应用 (支持JS执行)'),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ======================================================================
// JS 运行时管理器（修复版）
// ======================================================================
class JsRuntimeManager {
  static JavascriptRuntime? _runtime;

  static JavascriptRuntime get runtime {
    _runtime ??= _createRuntime();
    return _runtime!;
  }

  static JavascriptRuntime _createRuntime() {
    final js = getJavascriptRuntime();

    // 注入 console 实现（使用全局函数而非 onMessage）
    js.evaluate('''
      var console = {
        _logs: [],
        log: function() {
          var args = [];
          for (var i = 0; i < arguments.length; i++) {
            var a = arguments[i];
            args.push(typeof a === 'object' ? JSON.stringify(a) : String(a));
          }
          console._logs.push({level: 'log', msg: args.join(' ')});
        },
        warn: function() {
          var args = [];
          for (var i = 0; i < arguments.length; i++) {
            var a = arguments[i];
            args.push(typeof a === 'object' ? JSON.stringify(a) : String(a));
          }
          console._logs.push({level: 'warn', msg: args.join(' ')});
        },
        error: function() {
          var args = [];
          for (var i = 0; i < arguments.length; i++) {
            var a = arguments[i];
            args.push(typeof a === 'object' ? JSON.stringify(a) : String(a));
          }
          console._logs.push({level: 'error', msg: args.join(' ')});
        },
        info: function() {
          var args = [];
          for (var i = 0; i < arguments.length; i++) {
            var a = arguments[i];
            args.push(typeof a === 'object' ? JSON.stringify(a) : String(a));
          }
          console._logs.push({level: 'info', msg: args.join(' ')});
        },
        getLogs: function() {
          var logs = console._logs.slice();
          console._logs = [];
          return JSON.stringify(logs);
        },
        clearLogs: function() {
          console._logs = [];
        }
      };
      
      // setTimeout 模拟（同步执行）
      var setTimeout = function(fn, delay) {
        if (typeof fn === 'function') fn();
        return 0;
      };
      var setInterval = function(fn, delay) {
        if (typeof fn === 'function') fn();
        return 0;
      };
      var clearTimeout = function(id) {};
      var clearInterval = function(id) {};
    ''');

    return js;
  }

  /// 获取并清除 console 日志
  static List<Map<String, String>> getAndClearLogs() {
    final logs = <Map<String, String>>[];
    try {
      final result = runtime.evaluate('console.getLogs()');
      if (!result.isError && result.stringResult.isNotEmpty) {
        final list = jsonDecode(result.stringResult) as List;
        for (final item in list) {
          final map = item as Map;
          logs.add({
            'level': (map['level'] as String?) ?? 'log',
            'message': (map['msg'] as String?) ?? '',
          });
        }
      }
    } catch (_) {}
    return logs;
  }

  static void dispose() {
    _runtime?.dispose();
    _runtime = null;
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
  String _htmlContent =
      '<h2>欢迎使用</h2><p>支持 form 提交、input / button / select / textarea，以及 script 标签执行。</p>';
  bool _isLoading = false;
  String _currentUrl = '';
  final Map<int, _FormData> _formRegistry = {};

  // JS 控制台日志列表
  final List<Map<String, String>> _consoleLogs = [];
  bool _showConsole = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    JsRuntimeManager.dispose();
    super.dispose();
  }

  void _addConsoleLog(String level, String message) {
    if (mounted) {
      setState(() {
        _consoleLogs.add({
          'level': level,
          'message': message,
          'time': DateTime.now().toString().substring(11, 19),
        });
      });
    }
  }

  void _clearConsole() {
    setState(() => _consoleLogs.clear());
  }

  // ------------------------------------------------------------------
  // 获取表单数据
  // ------------------------------------------------------------------
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
  // 执行 JavaScript（修复版）
  // ------------------------------------------------------------------
  String _executeScript(String scriptContent) {
    if (scriptContent.trim().isEmpty) return '';

    final js = JsRuntimeManager.runtime;

    try {
      final result = js.evaluate(scriptContent);

      // 获取 console 日志
      final logs = JsRuntimeManager.getAndClearLogs();
      for (final log in logs) {
        _addConsoleLog(log['level']!, log['message']!);
      }

      if (result.isError) {
        final errorMsg = result.stringResult;
        _addConsoleLog('error', 'Script Error: $errorMsg');
        return '❌ $errorMsg';
      }

      if (result.stringResult.isNotEmpty &&
          result.stringResult != 'undefined' &&
          result.stringResult != 'null') {
        _addConsoleLog('log', '返回值: ${result.stringResult}');
      }

      return '';
    } catch (e) {
      _addConsoleLog('error', '执行异常: $e');
      return '❌ $e';
    }
  }

  // 从 HTML 中提取并执行所有 script 标签
  void _executeScriptsFromHtml(String html) {
    try {
      final document = dom.Document.html(html);
      final scripts = document.getElementsByTagName('script');

      for (final script in scripts) {
        final src = script.attributes['src'];
        final type = script.attributes['type']?.toLowerCase();

        // 跳过非 JavaScript 类型
        if (type != null &&
            type != 'text/javascript' &&
            type != 'application/javascript' &&
            type != 'module' &&
            type != '') {
          continue;
        }

        if (src != null) {
          // 外部脚本 - 异步加载
          _loadExternalScript(src);
        } else {
          // 内联脚本
          final content = script.text;
          if (content.trim().isNotEmpty) {
            _addConsoleLog('info', '执行内联脚本...');
            _executeScript(content);
          }
        }
      }
    } catch (e) {
      _addConsoleLog('error', '解析脚本标签失败: $e');
    }
  }

  // 加载外部脚本
  Future<void> _loadExternalScript(String src) async {
    final fullUrl = _resolveUrl(src);
    _addConsoleLog('info', '加载外部脚本: $fullUrl');

    try {
      final response = await http.get(
        Uri.parse(fullUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final content = _fixEncoding(response);
        _executeScript(content);
      } else {
        _addConsoleLog('error', '加载脚本失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      _addConsoleLog('error', '加载脚本异常: $e');
    }
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
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final html = _fixEncoding(response);
        setState(() => _htmlContent = html);
        _executeScriptsFromHtml(html);
      } else {
        setState(
            () => _htmlContent = '<p style="color:red">请求失败: ${response.statusCode}</p>');
      }
    } catch (e) {
      setState(
          () => _htmlContent = '<p style="color:red">请求出错: $e</p>');
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
      final data = Map.fromEntries(
          formData.values.entries.where((e) => e.key.isNotEmpty));
      http.Response response;
      if (formData.method == 'post') {
        response = await http.post(Uri.parse(fullUrl), headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Content-Type': 'application/x-www-form-urlencoded',
        }, body: data).timeout(const Duration(seconds: 10));
      } else {
        final queryString = data.entries
            .map((e) =>
                '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
            .join('&');
        final url = queryString.isNotEmpty ? '$fullUrl?$queryString' : fullUrl;
        response = await http.get(Uri.parse(url), headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        }).timeout(const Duration(seconds: 10));
      }
      setState(() {
        _currentUrl = fullUrl;
        _urlController.text = fullUrl;
        if (response.statusCode == 200) {
          final html = _fixEncoding(response);
          _htmlContent = html;
          _executeScriptsFromHtml(html);
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

  Widget? _buildHtmlInput(dom.Element element) {
    final type = element.attributes['type']?.toLowerCase() ?? 'text';
    final name = element.attributes['name'] ?? '';
    final value = element.attributes['value'] ?? '';
    final placeholder = element.attributes['placeholder'] ?? '';
    final formData = _getFormDataForElement(element);
    final onclick = element.attributes['onclick'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: _InputWrapper(
        type: type,
        placeholder: placeholder,
        value: value,
        name: name,
        formData: formData,
        onSubmit: formData != null ? () => _submitForm(formData) : null,
        onclick: onclick,
      ),
    );
  }

  Widget? _buildHtmlButton(dom.Element element) {
    final type = element.attributes['type']?.toLowerCase() ?? 'button';
    final text = element.innerHtml;
    final formData = _getFormDataForElement(element);
    final onclick = element.attributes['onclick'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: _FormButtonWrapper(
        type: type,
        text: text,
        formData: formData,
        onSubmit: formData != null ? () => _submitForm(formData) : null,
        onclick: onclick,
      ),
    );
  }

  Widget? _buildHtmlSelect(dom.Element element) {
    final name = element.attributes['name'] ?? '';
    final formData = _getFormDataForElement(element);
    final onchange = element.attributes['onchange'];
    final options = element.getElementsByTagName('option');
    final items = options.map((opt) {
      final label = opt.text.trim();
      final val = opt.attributes['value'] ?? label;
      return MapEntry(label, val);
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: _SelectWrapper(
        items: items,
        name: name,
        formData: formData,
        onchange: onchange,
      ),
    );
  }

  Widget? _buildHtmlTextarea(dom.Element element) {
    final name = element.attributes['name'] ?? '';
    final placeholder = element.attributes['placeholder'] ?? '';
    final value = element.text.trim();
    final formData = _getFormDataForElement(element);
    final oninput = element.attributes['oninput'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: _TextareaWrapper(
        name: name,
        placeholder: placeholder,
        value: value,
        formData: formData,
        oninput: oninput,
      ),
    );
  }

  // 构建 Script 标签
  Widget? _buildHtmlScript(dom.Element element) {
    final src = element.attributes['src'];
    final type = element.attributes['type'];
    final content = element.text.trim();

    // 外部脚本
    if (src != null && content.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange[300]!),
        ),
        child: Row(
          children: [
            Icon(Icons.javascript, color: Colors.orange[700], size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '外部脚本: $src',
                style: TextStyle(color: Colors.orange[700], fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    // 内联脚本
    if (content.isNotEmpty) {
      return _ScriptBlockWidget(
        scriptContent: content,
        type: type,
        onExecute: () => _executeScript(content),
      );
    }

    return const SizedBox.shrink();
  }

  // 控制台面板
  Widget _buildConsolePanel() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border(top: BorderSide(color: Colors.grey[600]!, width: 2)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF2D2D2D),
            child: Row(
              children: [
                const Text('控制台',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${_consoleLogs.length} 条日志',
                    style: TextStyle(color: Colors.grey[400], fontSize: 11)),
                const SizedBox(width: 16),
                InkWell(
                  onTap: _clearConsole,
                  child:
                      const Icon(Icons.clear_all, color: Colors.grey, size: 16),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => setState(() => _showConsole = false),
                  child: const Icon(Icons.close, color: Colors.grey, size: 16),
                ),
              ],
            ),
          ),
          Expanded(
            child: _consoleLogs.isEmpty
                ? const Center(
                    child: Text('暂无日志输出',
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 12)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _consoleLogs.length,
                    itemBuilder: (context, index) {
                      final log = _consoleLogs[index];
                      final color = _getLogColor(log['level']!);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('[${log['time']}] ',
                                style: const TextStyle(
                                    color: Colors.grey500,
                                    fontSize: 10,
                                    fontFamily: 'monospace')),
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(top: 5, right: 6),
                              decoration:
                                  BoxDecoration(color: color, shape: BoxShape.circle),
                            ),
                            Expanded(
                              child: Text(
                                log['message']!,
                                style: TextStyle(
                                    color: color,
                                    fontSize: 11,
                                    fontFamily: 'monospace'),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _getLogColor(String level) {
    switch (level) {
      case 'error':
        return Colors.red[400]!;
      case 'warn':
        return Colors.yellow[400]!;
      case 'info':
        return Colors.blue[400]!;
      default:
        return Colors.white70;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: _consoleLogs.isNotEmpty,
              label: Text(_consoleLogs.length.toString()),
              child: const Icon(Icons.terminal),
            ),
            onPressed: () => setState(() => _showConsole = !_showConsole),
            tooltip: '控制台',
          ),
          const SizedBox(width: 8),
        ],
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
                      prefixIcon: const Icon(Icons.language, size: 20),
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
                  border: Border.all(
                      width: 2, color: Theme.of(context).dividerColor)),
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
                    if (tag == 'script') return _buildHtmlScript(element);
                    return null;
                  },
                  textStyle: const TextStyle(fontSize: 16),
                  customStylesBuilder: (element) =>
                      {'margin': '0', 'padding': '0'},
                ),
              ),
            ),
          ),
          if (_showConsole) _buildConsolePanel(),
          SafeArea(
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[300],
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '当前 URL: $_currentUrl',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_consoleLogs.isNotEmpty && !_showConsole)
                    InkWell(
                      onTap: () => setState(() => _showConsole = true),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: _consoleLogs.any((l) => l['level'] == 'error')
                                ? Colors.red
                                : Colors.orange,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text('${_consoleLogs.length}',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black54)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// Script 代码块组件（修复 const 问题）
// ======================================================================
class _ScriptBlockWidget extends StatefulWidget {
  final String scriptContent;
  final String? type;
  final VoidCallback onExecute;

  const _ScriptBlockWidget({
    required this.scriptContent,
    this.type,
    required this.onExecute,
  });

  @override
  State<_ScriptBlockWidget> createState() => _ScriptBlockWidgetState();
}

class _ScriptBlockWidgetState extends State<_ScriptBlockWidget> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(8);
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF282C34),
        borderRadius: borderRadius,
        border: Border.all(color: Colors.orange[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF21252B),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(_expanded ? 0 : 8),
                  topRight: Radius.circular(_expanded ? 0 : 8),
                  bottomLeft: Radius.circular(_expanded ? 0 : 8),
                  bottomRight: Radius.circular(_expanded ? 0 : 8),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.javascript, color: Colors.orange[400], size: 18),
                  const SizedBox(width: 8),
                  Text(
                    widget.type ?? 'text/javascript',
                    style: const TextStyle(
                        color: Colors.grey400,
                        fontSize: 11,
                        fontFamily: 'monospace'),
                  ),
                  const Spacer(),
                  Text(
                    '${widget.scriptContent.split('\n').length} 行',
                    style: const TextStyle(color: Colors.grey500, fontSize: 10),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.grey[400],
                      size: 18),
                ],
              ),
            ),
          ),
          // 代码内容
          if (_expanded)
            Container(
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  widget.scriptContent,
                  style: TextStyle(
                    color: Colors.green[300],
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          // 操作栏
          if (_expanded)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: const BoxDecoration(
                color: Color(0xFF21252B),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: widget.onExecute,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('执行', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: Colors.green[400]),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ======================================================================
// Input 控件
// ======================================================================
class _InputWrapper extends StatefulWidget {
  final String type;
  final String placeholder;
  final String value;
  final String name;
  final _FormData? formData;
  final VoidCallback? onSubmit;
  final String? onclick;

  const _InputWrapper({
    required this.type,
    required this.placeholder,
    required this.value,
    required this.name,
    this.formData,
    this.onSubmit,
    this.onclick,
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
    _controller.addListener(_onTextChanged);
    widget.formData?.addListener(_onFormChanged);
  }

  void _onTextChanged() {
    if (widget.formData != null &&
        widget.name.isNotEmpty &&
        !['checkbox', 'radio', 'submit', 'reset', 'button', 'hidden']
            .contains(widget.type)) {
      widget.formData!.values[widget.name] = _controller.text;
    }
  }

  void _onFormChanged() {
    if (widget.type == 'radio' && widget.formData != null && mounted) {
      setState(
          () => _isChecked = widget.formData!.values[widget.name] == widget.value);
    }
  }

  void _handleOnclick() {
    if (widget.onclick != null && widget.onclick!.isNotEmpty) {
      JsRuntimeManager.runtime.evaluate(widget.onclick!);
      final logs = JsRuntimeManager.getAndClearLogs();
      for (final log in logs) {
        _addLogToConsole(log);
      }
    }
  }

  void _addLogToConsole(Map<String, String> log) {
    // 这里需要通过其他方式传递日志到父组件
    // 简化处理：直接使用 JS 运行时
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
          decoration: InputDecoration(
            hintText: widget.placeholder,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
          ),
        );
      case 'hidden':
        return const SizedBox.shrink();
      case 'checkbox':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: _isChecked,
              onChanged: (val) {
                setState(() => _isChecked = val ?? false);
                if (widget.formData != null && widget.name.isNotEmpty) {
                  widget.formData!
                      .setValue(widget.name, _isChecked ? widget.value : '');
                }
                _handleOnclick();
              },
            ),
            Text(widget.placeholder.isNotEmpty ? widget.placeholder : widget.name),
          ],
        );
      case 'radio':
        return GestureDetector(
          onTap: () {
            if (widget.formData != null && widget.name.isNotEmpty) {
              widget.formData!.setValue(widget.name, widget.value);
            }
            _handleOnclick();
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
                        color: _isChecked ? Colors.blue : Colors.grey, width: 2),
                  ),
                  child: _isChecked
                      ? Center(
                          child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                  shape: BoxShape.circle, color: Colors.blue)))
                      : null,
                ),
                const SizedBox(width: 8),
                Text(widget.placeholder.isNotEmpty ? widget.placeholder : widget.value),
              ],
            ),
          ),
        );
      case 'submit':
        return ElevatedButton(
          onPressed: () {
            _handleOnclick();
            widget.onSubmit?.call();
          },
          style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white),
          child: Text(widget.value.isNotEmpty ? widget.value : 'Submit'),
        );
      case 'reset':
        return ElevatedButton(
          onPressed: () {
            widget.formData?.values.clear();
            _controller.clear();
            setState(() => _isChecked = false);
            _handleOnclick();
          },
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey, foregroundColor: Colors.white),
          child: Text(widget.value.isNotEmpty ? widget.value : 'Reset'),
        );
      case 'button':
      default:
        return ElevatedButton(
          onPressed: _handleOnclick,
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              side: const BorderSide(color: Colors.grey)),
          child: Text(widget.value.isNotEmpty
              ? widget.value
              : (widget.type.toUpperCase())),
        );
    }
  }
}

// ======================================================================
// Button 控件
// ======================================================================
class _FormButtonWrapper extends StatelessWidget {
  final String type;
  final String text;
  final _FormData? formData;
  final VoidCallback? onSubmit;
  final String? onclick;

  const _FormButtonWrapper({
    required this.type,
    required this.text,
    this.formData,
    this.onSubmit,
    this.onclick,
  });

  void _handleOnclick() {
    if (onclick != null && onclick!.isNotEmpty) {
      JsRuntimeManager.runtime.evaluate(onclick!);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (type == 'submit') {
      return ElevatedButton(
        onPressed: () {
          _handleOnclick();
          onSubmit?.call();
        },
        style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white),
        child: Text(text.isEmpty ? 'Submit' : text),
      );
    }
    if (type == 'reset') {
      return ElevatedButton(
        onPressed: () {
          formData?.values.clear();
          _handleOnclick();
        },
        style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey, foregroundColor: Colors.white),
        child: Text(text.isEmpty ? 'Reset' : text),
      );
    }
    return ElevatedButton(
      onPressed: _handleOnclick,
      style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          side: const BorderSide(color: Colors.grey)),
      child: Text(text.isEmpty ? 'Button' : text),
    );
  }
}

// ======================================================================
// Select 控件
// ======================================================================
class _SelectWrapper extends StatefulWidget {
  final List<MapEntry<String, String>> items;
  final String name;
  final _FormData? formData;
  final String? onchange;

  const _SelectWrapper({
    required this.items,
    required this.name,
    this.formData,
    this.onchange,
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

  void _handleOnchange(String? val) {
    if (widget.onchange != null && widget.onchange!.isNotEmpty) {
      final js = JsRuntimeManager.runtime;
      js.evaluate('var _this = { value: "$val" };');
      js.evaluate(widget.onchange!.replaceAll('this.', '_this.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue:
          widget.items.any((e) => e.value == _selectedValue) ? _selectedValue : null,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      items: widget.items
          .map((item) => DropdownMenuItem<String>(value: item.value, child: Text(item.key)))
          .toList(),
      onChanged: (val) {
        setState(() => _selectedValue = val);
        if (widget.formData != null && widget.name.isNotEmpty) {
          widget.formData!.values[widget.name] = val ?? '';
        }
        _handleOnchange(val);
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
  final String? oninput;

  const _TextareaWrapper({
    required this.name,
    required this.placeholder,
    required this.value,
    this.formData,
    this.oninput,
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
      if (widget.oninput != null && widget.oninput!.isNotEmpty) {
        final js = JsRuntimeManager.runtime;
        final escaped = _controller.text.replaceAll('"', '\\"').replaceAll('\n', '\\n');
        js.evaluate('var _this = { value: "$escaped" };');
        js.evaluate(widget.oninput!.replaceAll('this.', '_this.'));
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
      decoration:
          InputDecoration(hintText: widget.placeholder, border: const OutlineInputBorder()),
    );
  }
}
