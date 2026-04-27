import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;
// 如果你要用 flutter_js_pro，把这行换成 import 'package:flutter_js_pro/js.dart';
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
// JS 运行时管理器 (注入终极浏览器沙盒环境)
// ======================================================================
class JsRuntimeManager {
  static JavascriptRuntime? _runtime;

  static JavascriptRuntime get runtime {
    _runtime ??= _createRuntime();
    return _runtime!;
  }

  static JavascriptRuntime _createRuntime() {
    // 如果使用 flutter_js_pro，将 getJavascriptRuntime() 换成 JsPlus()
    final js = getJavascriptRuntime();
    
    // 1. 注入超级完整的浏览器全局模拟对象（解决原生平台无 DOM/BOM 的问题）
    js.evaluate(r'''
      var noop = function() {};
      var FakeElement = function(tag) {
        return {
          tagName: (tag || '').toUpperCase(),
          style: {},
          setAttribute: noop,
          getAttribute: function() { return null; },
          removeAttribute: noop,
          appendChild: noop,
          removeChild: noop,
          insertBefore: noop,
          replaceChild: noop,
          addEventListener: noop,
          removeEventListener: noop,
          dispatchEvent: function() { return true; },
          textContent: '',
          innerHTML: '',
          innerText: '',
          outerHTML: '',
          value: '',
          className: '',
          id: '',
          children: [],
          childNodes: [],
          parentNode: null,
          offsetWidth: 0,
          offsetHeight: 0,
          getBoundingClientRect: function() { return {top:0, left:0, width:0, height:0}; },
          focus: noop,
          blur: noop,
          click: noop,
          cloneNode: function() { return this; },
          querySelector: function() { return null; },
          querySelectorAll: function() { return []; }
        };
      };

      var document = {
        createElement: function(tag) { return new FakeElement(tag); },
        createElementNS: function(ns, tag) { return new FakeElement(tag); },
        createTextNode: function(text) { return { textContent: text }; },
        getElementById: function() { return null; },
        getElementsByClassName: function() { return []; },
        getElementsByTagName: function() { return []; },
        querySelector: function() { return null; },
        querySelectorAll: function() { return []; },
        body: new FakeElement('body'),
        head: new FakeElement('head'),
        documentElement: new FakeElement('html'),
        readyState: 'complete',
        cookie: '',
        addEventListener: noop,
        removeEventListener: noop,
        createEvent: function() { return { initEvent: noop }; }
      };

      var window = {
        document: document,
        location: { href: '', hostname: '', pathname: '/', search: '', protocol: 'https:', replace: noop, assign: noop, reload: noop },
        navigator: { userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36', language: 'zh-CN', platform: 'Win32', onLine: true, appVersion: '5.0' },
        localStorage: { getItem: function(){return null;}, setItem: noop, removeItem: noop, clear: noop, length: 0 },
        sessionStorage: { getItem: function(){return null;}, setItem: noop, removeItem: noop, clear: noop, length: 0 },
        addEventListener: noop,
        removeEventListener: noop,
        getComputedStyle: function() { return { getPropertyValue: function() { return ''; } }; },
        setTimeout: function(fn, t) { if(typeof fn==='function') try{fn();}catch(e){} return 0; },
        setInterval: function(fn, t) { if(typeof fn==='function') try{fn();}catch(e){} return 0; },
        clearTimeout: noop,
        clearInterval: noop,
        requestAnimationFrame: function(fn) { if(typeof fn==='function') try{fn();}catch(e){} return 0; },
        cancelAnimationFrame: noop,
        scroll: noop,
        scrollTo: noop,
        open: function() { return window; },
        close: noop,
        postMessage: noop,
        fetch: function() { return Promise.resolve({ json: function(){return Promise.resolve({});}, text: function(){return Promise.resolve("");} }); },
        alert: noop,
        confirm: function() { return false; },
        prompt: function() { return null; },
        Image: function() { return new FakeElement('img'); },
        XMLHttpRequest: function() { return { open: noop, send: noop, setRequestHeader: noop, addEventListener: noop, readyState: 4, status: 200, responseText: '', response: '' }; },
        atob: function(s) { return s; },
        btoa: function(s) { return s; },
        innerWidth: 1920,
        innerHeight: 1080,
        devicePixelRatio: 1,
        screen: { width: 1920, height: 1080 },
        history: { pushState: noop, replaceState: noop, go: noop, back: noop, forward: noop },
        crypto: { getRandomValues: function(arr) { for(var i=0;i<arr.length;i++) arr[i]=Math.floor(Math.random()*256); return arr; } }
      };

      if (typeof Promise === 'undefined') {
        var Promise = function(fn) { if(typeof fn === 'function') fn(function(){}, function(){}); };
      }
      var self = window;
      var globalThis = window;
      var Node = { ELEMENT_NODE: 1, TEXT_NODE: 3 };
      var navigator = window.navigator;
      var location = window.location;
      var localStorage = window.localStorage;
      var sessionStorage = window.sessionStorage;
    ''');

    // 2. 注入 console 拦截 (覆盖上面的空函数，确保日志被捕获)
    js.evaluate(r'''
      var console = {
        _logs: [],
        log: function() { console._logs.push({l:'log', m: Array.from(arguments).join(' ')}); },
        warn: function() { console._logs.push({l:'warn', m: Array.from(arguments).join(' ')}); },
        error: function() { console._logs.push({l:'error', m: Array.from(arguments).join(' ')}); },
        info: function() { console._logs.push({l:'info', m: Array.from(arguments).join(' ')}); },
        getLogs: function() { var l = console._logs; console._logs = []; return JSON.stringify(l); }
      };
    ''');

    return js;
  }

  static List<Map<String, String>> getAndClearLogs() {
    final logs = <Map<String, String>>[];
    try {
      final result = runtime.evaluate('console.getLogs()');
      if (!result.isError && result.stringResult.isNotEmpty) {
        final list = jsonDecode(result.stringResult) as List;
        for (final item in list) {
          logs.add({'level': item['l'] ?? 'log', 'message': item['m'] ?? ''});
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
  String _htmlContent = '<h2>欢迎使用</h2><p>完整支持 form 提交、input / button / select / textarea 及 script 执行。</p>';
  bool _isLoading = false;
  String _currentUrl = '';
  final Map<int, _FormData> _formRegistry = {};
  final List<Map<String, String>> _consoleLogs = [];
  bool _showConsole = false;

  @override
  void dispose() {
    JsRuntimeManager.dispose();
    super.dispose();
  }

  void _addLog(String level, String msg) {
    if (mounted) {
      setState(() {
        _consoleLogs.add({
          'level': level,
          'message': msg,
          'time': DateTime.now().toString().substring(11, 19),
        });
      });
    }
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
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (_currentUrl.isEmpty) {
      return 'https://$url';
    }
    final uri = Uri.parse(_currentUrl);
    if (url.startsWith('/')) {
      return '${uri.scheme}://${uri.host}$url';
    }
    final path = uri.path;
    final lastSlash = path.lastIndexOf('/');
    final basePath = lastSlash > 0 ? path.substring(0, lastSlash) : '';
    return '${uri.scheme}://${uri.host}$basePath/$url';
  }

  String _fixEncoding(http.Response response) {
    final contentType = response.headers['content-type'] ?? '';
    if (contentType.toLowerCase().contains('charset=')) {
      return response.body;
    }
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

  String _execScript(String script) {
    if (script.trim().isEmpty) {
      return '';
    }
    try {
      final result = JsRuntimeManager.runtime.evaluate(script);
      final logs = JsRuntimeManager.getAndClearLogs();
      for (final log in logs) {
        _addLog(log['level']!, log['message']!);
      }
      // 修复：彻底移除 stackTrace
      if (result.isError) {
        _addLog('error', 'Script Error: ${result.stringResult}');
      }
      return '';
    } catch (e) {
      _addLog('error', '异常: $e');
      return '❌';
    }
  }

  void _execScriptsFromHtml(String html) {
    try {
      final doc = dom.Document.html(html);
      for (final script in doc.getElementsByTagName('script')) {
        final type = script.attributes['type']?.toLowerCase();
        if (type != null && type != 'text/javascript' && type != 'application/javascript' && type != '') {
          continue;
        }
        final src = script.attributes['src'];
        if (src != null) {
          _loadExternalScript(src);
        } else if (script.text.trim().isNotEmpty) {
          _addLog('info', '执行内联脚本...');
          _execScript(script.text);
        }
      }
    } catch (e) {
      _addLog('error', '解析HTML失败: $e');
    }
  }

  Future<void> _loadExternalScript(String src) async {
    final fullUrl = _resolveUrl(src);
    _addLog('info', '加载外部脚本: $fullUrl');
    try {
      final res = await http.get(Uri.parse(fullUrl), headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        // 强化：强制 utf8 解码，允许残缺字符，解决特殊字符引起的脚本崩溃错误
        final scriptContent = utf8.decode(res.bodyBytes, allowMalformed: true);
        _execScript(scriptContent);
      } else {
        _addLog('error', '加载失败: HTTP ${res.statusCode}');
      }
    } catch (e) {
      _addLog('error', '加载异常: $e');
    }
  }

  Future<void> _fetchWebContent(String url) async {
    if (url.isEmpty) {
      return;
    }
    final fullUrl = _resolveUrl(url);
    setState(() {
      _isLoading = true;
      _currentUrl = fullUrl;
      _urlController.text = fullUrl;
      _formRegistry.clear();
    });
    try {
      final response = await http.get(Uri.parse(fullUrl), headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final html = _fixEncoding(response);
        setState(() => _htmlContent = html);
        _execScriptsFromHtml(html);
      } else {
        setState(() => _htmlContent = '<p style="color:red">请求失败: ${response.statusCode}</p>');
      }
    } catch (e) {
      setState(() => _htmlContent = '<p style="color:red">请求出错: $e</p>');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submitForm(_FormData formData) async {
    final fullUrl = formData.action.isNotEmpty ? _resolveUrl(formData.action) : _currentUrl;
    if (fullUrl.isEmpty) {
      return;
    }
    setState(() => _isLoading = true);
    try {
      final data = Map.fromEntries(formData.values.entries.where((e) => e.key.isNotEmpty));
      http.Response response;
      if (formData.method == 'post') {
        response = await http.post(Uri.parse(fullUrl), headers: {'User-Agent': 'Mozilla/5.0', 'Content-Type': 'application/x-www-form-urlencoded'}, body: data).timeout(const Duration(seconds: 10));
      } else {
        final qs = data.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');
        response = await http.get(Uri.parse(qs.isNotEmpty ? '$fullUrl?$qs' : fullUrl), headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 10));
      }
      setState(() {
        _currentUrl = fullUrl;
        _urlController.text = fullUrl;
        if (response.statusCode == 200) {
          final html = _fixEncoding(response);
          _htmlContent = html;
          _execScriptsFromHtml(html);
        } else {
          _htmlContent = '<p style="color:red">提交返回状态码: ${response.statusCode}</p>';
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('提交出错: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget? _buildHtmlInput(dom.Element element) {
    final type = element.attributes['type']?.toLowerCase() ?? 'text';
    final formData = _getFormDataForElement(element);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: _InputWrapper(
        type: type,
        placeholder: element.attributes['placeholder'] ?? '',
        value: element.attributes['value'] ?? '',
        name: element.attributes['name'] ?? '',
        formData: formData,
        onSubmit: formData != null ? () => _submitForm(formData) : null,
        onclick: element.attributes['onclick'],
      ),
    );
  }

  Widget? _buildHtmlButton(dom.Element element) {
    final formData = _getFormDataForElement(element);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: _FormButtonWrapper(
        type: element.attributes['type']?.toLowerCase() ?? 'button',
        text: element.innerHtml,
        formData: formData,
        onSubmit: formData != null ? () => _submitForm(formData) : null,
        onclick: element.attributes['onclick'],
      ),
    );
  }

  Widget? _buildHtmlSelect(dom.Element element) {
    final formData = _getFormDataForElement(element);
    final items = element.getElementsByTagName('option').map((o) => MapEntry(o.text.trim(), o.attributes['value'] ?? o.text.trim())).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: _SelectWrapper(
        items: items,
        name: element.attributes['name'] ?? '',
        formData: formData,
        onchange: element.attributes['onchange'],
      ),
    );
  }

  Widget? _buildHtmlTextarea(dom.Element element) {
    final formData = _getFormDataForElement(element);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: _TextareaWrapper(
        name: element.attributes['name'] ?? '',
        placeholder: element.attributes['placeholder'] ?? '',
        value: element.text.trim(),
        formData: formData,
        oninput: element.attributes['oninput'],
      ),
    );
  }

  Widget? _buildHtmlScript(dom.Element element) {
    final src = element.attributes['src'];
    final content = element.text.trim();
    if (src != null && content.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange[300]!)),
        child: Row(children: [Icon(Icons.javascript, color: Colors.orange[700], size: 20), const SizedBox(width: 8), Expanded(child: Text('外部脚本: $src', style: TextStyle(color: Colors.orange[700], fontSize: 12)))]),
      );
    }
    if (content.isNotEmpty) {
      return _ScriptBlock(scriptContent: content, type: element.attributes['type'], onExecute: () => _execScript(content));
    }
    return const SizedBox.shrink();
  }

  Color _getColor(String l) {
    if (l == 'error') {
      return Colors.red[400]!;
    } else if (l == 'warn') {
      return Colors.yellow[400]!;
    } else if (l == 'info') {
      return Colors.blue[400]!;
    } else {
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
          )
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
                  onPressed: _isLoading ? null : () => _fetchWebContent(_urlController.text),
                  child: _isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('访问'),
                )
              ],
            ),
          ),
          if (_isLoading) {
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: LinearProgressIndicator(minHeight: 4, backgroundColor: Colors.transparent),
            )
          },
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: Border.all(width: 2, color: Theme.of(context).dividerColor)),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: HtmlWidget(
                  _htmlContent,
                  onTapUrl: (url) {
                    _fetchWebContent(url);
                    return true;
                  },
                  customWidgetBuilder: (e) {
                    final t = e.localName;
                    if (t == 'input') {
                      return _buildHtmlInput(e);
                    }
                    if (t == 'button') {
                      return _buildHtmlButton(e);
                    }
                    if (t == 'select') {
                      return _buildHtmlSelect(e);
                    }
                    if (t == 'textarea') {
                      return _buildHtmlTextarea(e);
                    }
                    if (t == 'option') {
                      return const SizedBox.shrink();
                    }
                    if (t == 'script') {
                      return _buildHtmlScript(e);
                    }
                    return null;
                  },
                  textStyle: const TextStyle(fontSize: 16),
                  customStylesBuilder: (e) => {'margin': '0', 'padding': '0'},
                ),
              ),
            ),
          ),
          if (_showConsole) {
            Container(
              height: 200,
              color: const Color(0xFF1E1E1E),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: const Color(0xFF2D2D2D),
                    child: Row(
                      children: [
                        const Text('控制台', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Text('${_consoleLogs.length} 条', style: TextStyle(color: Colors.grey[400]!, fontSize: 11)),
                        InkWell(onTap: () => setState(() => _consoleLogs.clear()), child: const Icon(Icons.clear_all, color: Colors.grey, size: 16)),
                        InkWell(onTap: () => setState(() => _showConsole = false), child: const Icon(Icons.close, color: Colors.grey, size: 16))
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _consoleLogs.length,
                      itemBuilder: (c, i) {
                        final log = _consoleLogs[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('[${log['time']}] ${log['message']}', style: TextStyle(color: _getColor(log['level']!), fontSize: 11, fontFamily: 'monospace')),
                        );
                      },
                    ),
                  )
                ],
              ),
            )
          },
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

// 简化版 Script 块
class _ScriptBlock extends StatefulWidget {
  final String scriptContent;
  final String? type;
  final VoidCallback onExecute;
  const _ScriptBlock({required this.scriptContent, this.type, required this.onExecute});

  @override
  State<_ScriptBlock> createState() => _ScriptBlockState();
}

class _ScriptBlockState extends State<_ScriptBlock> {
  bool _exp = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFF282C34), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange[300]!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _exp = !_exp),
            child: Container(
              padding: const EdgeInsets.all(8),
              color: const Color(0xFF21252B),
              child: Row(
                children: [
                  Icon(Icons.javascript, color: Colors.orange[400], size: 18),
                  const SizedBox(width: 8),
                  Text(widget.type ?? 'text/javascript', style: TextStyle(color: Colors.grey[400]!, fontSize: 11)),
                  const Spacer(),
                  Text('${widget.scriptContent.split('\n').length} 行', style: TextStyle(color: Colors.grey[500]!, fontSize: 10))
                ],
              ),
            ),
          ),
          if (_exp) {
            Container(
              padding: const EdgeInsets.all(12),
              child: Text(widget.scriptContent, style: TextStyle(color: Colors.green[300]!, fontSize: 12, fontFamily: 'monospace')),
            )
          },
          if (_exp) {
            Container(
              padding: const EdgeInsets.all(8),
              color: const Color(0xFF21252B),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: widget.onExecute,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('执行'),
                    style: TextButton.styleFrom(foregroundColor: Colors.green[400]),
                  )
                ],
              ),
            )
          }
        ],
      ),
    );
  }
}

// ======================================================================
// 以下为表单控件
// ======================================================================
class _InputWrapper extends StatefulWidget {
  final String type, placeholder, value, name;
  final _FormData? formData;
  final VoidCallback? onSubmit;
  final String? onclick;
  const _InputWrapper({required this.type, required this.placeholder, required this.value, required this.name, this.formData, this.onSubmit, this.onclick});

  @override
  State<_InputWrapper> createState() => _InputWrapperState();
}

class _InputWrapperState extends State<_InputWrapper> {
  late TextEditingController _c;
  bool _chk = false;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.value);
    if (widget.formData != null && widget.name.isNotEmpty) {
      if (widget.type == 'checkbox') {
        _chk = widget.value.isNotEmpty;
        widget.formData!.setValue(widget.name, _chk ? widget.value : '');
      } else if (widget.type == 'radio') {
        _chk = widget.formData!.values[widget.name] == widget.value;
      } else {
        widget.formData!.values[widget.name] = widget.value;
      }
    }
    _c.addListener(() {
      if (widget.formData != null && widget.name.isNotEmpty && !['checkbox', 'radio', 'submit', 'reset', 'button', 'hidden'].contains(widget.type)) {
        widget.formData!.values[widget.name] = _c.text;
      }
    });
    widget.formData?.addListener(() {
      if (widget.type == 'radio' && mounted) {
        setState(() => _chk = widget.formData!.values[widget.name] == widget.value);
      }
    });
  }

  void _click() {
    if (widget.onclick != null) {
      JsRuntimeManager.runtime.evaluate(widget.onclick!);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (['text', 'search', 'email', 'password', 'url', 'tel', 'number', 'date'].contains(widget.type)) {
      return TextField(
        controller: _c,
        obscureText: widget.type == 'password',
        decoration: InputDecoration(
          hintText: widget.placeholder,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
        ),
      );
    }
    if (widget.type == 'hidden') {
      return const SizedBox.shrink();
    }
    if (widget.type == 'checkbox') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: _chk,
            onChanged: (v) {
              setState(() => _chk = v ?? false);
              if (widget.formData != null && widget.name.isNotEmpty) {
                widget.formData!.setValue(widget.name, _chk ? widget.value : '');
              }
              _click();
            },
          ),
          Text(widget.placeholder.isNotEmpty ? widget.placeholder : widget.name)
        ],
      );
    }
    if (widget.type == 'radio') {
      return GestureDetector(
        onTap: () {
          if (widget.formData != null && widget.name.isNotEmpty) {
            widget.formData!.setValue(widget.name, widget.value);
          }
          _click();
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _chk ? Colors.blue : Colors.grey, width: 2)),
              child: _chk ? Center(child: Container(width: 10, height: 10, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.blue))) : null,
            ),
            const SizedBox(width: 8),
            Text(widget.placeholder.isNotEmpty ? widget.placeholder : widget.value)
          ],
        ),
      );
    }
    if (widget.type == 'submit') {
      return ElevatedButton(
        onPressed: () {
          _click();
          widget.onSubmit?.call();
        },
        style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white),
        child: Text(widget.value.isNotEmpty ? widget.value : 'Submit'),
      );
    }
    if (widget.type == 'reset') {
      return ElevatedButton(
        onPressed: () {
          widget.formData?.values.clear();
          _c.clear();
          setState(() => _chk = false);
          _click();
        },
        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, foregroundColor: Colors.white),
        child: Text(widget.value.isNotEmpty ? widget.value : 'Reset'),
      );
    }
    return ElevatedButton(
      onPressed: _click,
      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black87, side: const BorderSide(color: Colors.grey)),
      child: Text(widget.value.isNotEmpty ? widget.value : widget.type.toUpperCase()),
    );
  }
}

class _FormButtonWrapper extends StatelessWidget {
  final String type, text;
  final _FormData? formData;
  final VoidCallback? onSubmit;
  final String? onclick;
  const _FormButtonWrapper({required this.type, required this.text, this.formData, this.onSubmit, this.onclick});

  @override
  Widget build(BuildContext context) {
    void click() {
      if (onclick != null) {
        JsRuntimeManager.runtime.evaluate(onclick!);
      }
    }
    if (type == 'submit') {
      return ElevatedButton(
        onPressed: () {
          click();
          onSubmit?.call();
        },
        style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white),
        child: Text(text.isEmpty ? 'Submit' : text),
      );
    }
    if (type == 'reset') {
      return ElevatedButton(
        onPressed: () {
          formData?.values.clear();
          click();
        },
        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, foregroundColor: Colors.white),
        child: Text(text.isEmpty ? 'Reset' : text),
      );
    }
    return ElevatedButton(
      onPressed: click,
      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black87, side: const BorderSide(color: Colors.grey)),
      child: Text(text.isEmpty ? 'Button' : text),
    );
  }
}

class _SelectWrapper extends StatefulWidget {
  final List<MapEntry<String, String>> items;
  final String name;
  final _FormData? formData;
  final String? onchange;
  const _SelectWrapper({required this.items, required this.name, this.formData, this.onchange});

  @override
  State<_SelectWrapper> createState() => _SelectWrapperState();
}

class _SelectWrapperState extends State<_SelectWrapper> {
  String? _val;

  @override
  void initState() {
    super.initState();
    if (widget.items.isNotEmpty) {
      _val = widget.items.first.value;
    }
    if (widget.formData != null && widget.name.isNotEmpty) {
      widget.formData!.values[widget.name] = _val ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: widget.items.any((e) => e.value == _val) ? _val : null,
      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
      items: widget.items.map((i) => DropdownMenuItem(value: i.value, child: Text(i.key))).toList(),
      onChanged: (v) {
        setState(() => _val = v);
        if (widget.formData != null && widget.name.isNotEmpty) {
          widget.formData!.values[widget.name] = v ?? '';
        }
        if (widget.onchange != null) {
          JsRuntimeManager.runtime.evaluate('var _this={value:"$v"}; ${widget.onchange!.replaceAll("this.", "_this.")}');
        }
      },
    );
  }
}

class _TextareaWrapper extends StatefulWidget {
  final String name, placeholder, value;
  final _FormData? formData;
  final String? oninput;
  const _TextareaWrapper({required this.name, required this.placeholder, required this.value, this.formData, this.oninput});

  @override
  State<_TextareaWrapper> createState() => _TextareaWrapperState();
}

class _TextareaWrapperState extends State<_TextareaWrapper> {
  late TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.value);
    if (widget.formData != null && widget.name.isNotEmpty) {
      widget.formData!.values[widget.name] = widget.value;
    }
    _c.addListener(() {
      if (widget.formData != null && widget.name.isNotEmpty) {
        widget.formData!.values[widget.name] = _c.text;
      }
      if (widget.oninput != null) {
        JsRuntimeManager.runtime.evaluate('var _this={value:"${_c.text.replaceAll('"', '\\"').replaceAll('\n', '\\n')}"}; ${widget.oninput!.replaceAll("this.", "_this.")}');
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _c,
    maxLines: 4,
    decoration: InputDecoration(hintText: widget.placeholder, border: const OutlineInputBorder()),
  );
}
