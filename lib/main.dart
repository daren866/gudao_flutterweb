import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '移动端浏览器',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif',
      ),
      home: const MyHomePage(title: '移动端浏览器 (CSS完全兼容)'),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ======================================================================
// 增强版CSS解析器
// ======================================================================
class _MobileCssParser {
  final List<_CssRule> _rules = [];
  final Map<dom.Element, Map<String, String>> _styleCache = {};
  String _baseUrl = '';
  double _viewportWidth = 375;
  double _viewportHeight = 812;
  double _devicePixelRatio = 2.0;
  
  static final Map<String, Map<String, String>> _userAgentStyles = {
    '*': {
      'margin': '0', 'padding': '0', 'box-sizing': 'border-box',
      '-webkit-tap-highlight-color': 'transparent',
    },
    'html': {'font-size': '14px', 'scroll-behavior': 'smooth'},
    'body': {
      'font-family': '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif',
      'line-height': '1.5', 'margin': '0', 'padding': '0',
    },
    'div': {'display': 'block'},
    'span': {'display': 'inline'},
    'p': {'display': 'block', 'margin': '0 0 16px 0'},
    'h1': {'display': 'block', 'font-size': '2em', 'font-weight': 'bold'},
    'h2': {'display': 'block', 'font-size': '1.5em', 'font-weight': 'bold'},
    'h3': {'display': 'block', 'font-size': '1.17em', 'font-weight': 'bold'},
    'a': {'text-decoration': 'none', 'color': '#007aff'},
    'img': {'max-width': '100%', 'height': 'auto', 'display': 'inline-block'},
    'button': {
      'display': 'inline-block', 'min-height': '44px', 'min-width': '44px',
      'padding': '12px 20px', 'font-size': '16px', 'border-radius': '8px', 'border': 'none',
    },
    'input': {
      'display': 'inline-block', 'min-height': '44px', 'padding': '8px 12px', 'font-size': '16px',
    },
  };

  final List<_MediaQuery> _mediaQueries = [];

  void clear() {
    _rules.clear();
    _mediaQueries.clear();
    _styleCache.clear();
  }

  void setBaseUrl(String url) => _baseUrl = url;

  void setViewport({double width = 375, double height = 812, double pixelRatio = 2.0}) {
    _viewportWidth = width;
    _viewportHeight = height;
    _devicePixelRatio = pixelRatio;
  }

  void parseViewportMeta(String html) {
    final viewportRegex = RegExp(r'<meta[^>]+name="viewport"[^>]+content="([^"]*)"', caseSensitive: false);
    final match = viewportRegex.firstMatch(html);
    if (match != null) {
      final content = match.group(1) ?? '';
      for (final part in content.split(',')) {
        final trimmed = part.trim();
        if (trimmed.startsWith('width=')) {
          final width = trimmed.substring(6);
          if (width != 'device-width') {
            _viewportWidth = double.tryParse(width) ?? 375;
          }
        }
      }
    }
  }

  Future<void> parseFromHtml(String html, {http.Client? client, double screenWidth = 375}) async {
    clear();
    parseViewportMeta(html);
    _applyUserAgentStyles();
    await _parseStyleTags(html);
    if (client != null && _baseUrl.isNotEmpty) {
      await _fetchExternalStylesheets(html, client);
    }
    _applyMediaQueries(screenWidth);
    _rules.sort((a, b) => b.specificity.compareTo(a.specificity));
  }

  void _applyUserAgentStyles() {
    _userAgentStyles.forEach((selector, properties) {
      _rules.add(_CssRule(
        selector: selector,
        properties: Map.from(properties),
        specificity: selector == '*' ? 0 : 10,
        source: CssSource.userAgent,
      ));
    });
  }

  Future<void> _parseStyleTags(String html) async {
    final styleRegex = RegExp(r'<style[^>]*>(.*?)</style>', dotAll: true);
    for (final match in styleRegex.allMatches(html)) {
      _parseCssText(match.group(1)?.trim() ?? '', CssSource.styleTag);
    }
  }

  Future<void> _fetchExternalStylesheets(String html, http.Client client) async {
    final document = html_parser.parse(html);
    for (final link in document.querySelectorAll('link[rel="stylesheet"]')) {
      final href = link.attributes['href'];
      if (href == null || href.isEmpty) continue;
      try {
        final cssUrl = _resolveUrl(href);
        final response = await client.get(Uri.parse(cssUrl), headers: {
          'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15',
        }).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          _parseCssText(response.body, CssSource.external);
        }
      } catch (_) {}
    }
  }

  String _resolveUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final baseUri = Uri.parse(_baseUrl);
    if (url.startsWith('/')) return '${baseUri.scheme}://${baseUri.host}$url';
    final path = baseUri.path;
    final lastSlash = path.lastIndexOf('/');
    final basePath = lastSlash > 0 ? path.substring(0, lastSlash + 1) : '/';
    return '${baseUri.scheme}://${baseUri.host}$basePath$url';
  }

  void _parseCssText(String cssText, CssSource source) {
    final cleanCss = cssText.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    _extractMediaQueries(cleanCss);
    var normalCss = cleanCss.replaceAll(RegExp(r'@media[^{]+\{[^}]*\}', dotAll: true), '');
    
    for (final block in RegExp(r'([^{]+)\{([^}]*)\}').allMatches(normalCss)) {
      final selectorsStr = block.group(1)?.trim() ?? '';
      final propertiesStr = block.group(2)?.trim() ?? '';
      if (propertiesStr.isEmpty) continue;
      
      final properties = _parseProperties(propertiesStr);
      if (properties.isEmpty) continue;
      
      final cleanSelector = selectorsStr.replaceAll(RegExp(r':(active|hover|focus|visited)'), '');
      final isActive = selectorsStr.contains(':active');
      
      for (final selector in cleanSelector.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
        _rules.add(_CssRule(
          selector: selector,
          properties: Map.from(properties),
          specificity: _calculateSpecificity(selector),
          source: source,
          isActive: isActive,
        ));
      }
    }
  }

  void _extractMediaQueries(String cssText) {
    for (final match in RegExp(r'@media\s+([^{]+)\{([^}]*)\}', dotAll: true).allMatches(cssText)) {
      final condition = match.group(1)?.trim() ?? '';
      final rulesCss = match.group(2)?.trim() ?? '';
      final query = _MediaQuery(condition: condition, source: CssSource.styleTag);
      
      for (final block in RegExp(r'([^{]+)\{([^}]*)\}').allMatches(rulesCss)) {
        final selector = block.group(1)?.trim() ?? '';
        final properties = _parseProperties(block.group(2)?.trim() ?? '');
        if (selector.isNotEmpty && properties.isNotEmpty) {
          query.rules.add(_CssRule(
            selector: selector, properties: properties,
            specificity: _calculateSpecificity(selector), source: CssSource.styleTag,
          ));
        }
      }
      _mediaQueries.add(query);
    }
  }

  void _applyMediaQueries(double screenWidth) {
    for (final query in _mediaQueries) {
      if (query.matches(screenWidth, _viewportHeight, _devicePixelRatio)) {
        _rules.addAll(query.rules);
      }
    }
  }

  Map<String, String> _parseProperties(String propertiesStr) {
    final props = <String, String>{};
    for (final match in RegExp(r'([\w-]+)\s*:\s*([^;]+);?').allMatches(propertiesStr)) {
      final key = match.group(1)?.trim().toLowerCase() ?? '';
      final value = match.group(2)?.trim() ?? '';
      if (key.isNotEmpty && value.isNotEmpty) props[key] = value;
    }
    return props;
  }

  int _calculateSpecificity(String selector) {
    int score = 0;
    score += '#'.allMatches(selector).length * 10000;
    score += '.'.allMatches(selector).length * 100;
    score += '['.allMatches(selector).length * 100;
    score += ':'.allMatches(selector).length * 10;
    if (RegExp(r'^[a-zA-Z]+').hasMatch(selector)) score += 1;
    return score;
  }

  Map<String, String> getComputedStyle(dom.Element element) {
    if (_styleCache.containsKey(element)) return Map.from(_styleCache[element]!);
    
    final styles = <String, String>{};
    if (_userAgentStyles.containsKey('*')) styles.addAll(_userAgentStyles['*']!);
    
    final tagName = element.localName?.toLowerCase() ?? '';
    if (_userAgentStyles.containsKey(tagName)) styles.addAll(_userAgentStyles[tagName]!);
    
    for (final rule in _rules) {
      if (_selectorMatches(element, rule.selector)) styles.addAll(rule.properties);
    }
    
    final inlineStyle = element.attributes['style'];
    if (inlineStyle != null && inlineStyle.isNotEmpty) {
      styles.addAll(_parseProperties(inlineStyle));
    }
    
    styles.forEach((key, value) => styles[key] = _resolveCssValue(value));
    _styleCache[element] = Map.from(styles);
    return styles;
  }

  String _resolveCssValue(String value) {
    value = value.replaceAllMapped(RegExp(r'(\d+\.?\d*)vw'), (m) => '${(double.parse(m.group(1)!) / 100 * _viewportWidth).round()}px');
    value = value.replaceAllMapped(RegExp(r'(\d+\.?\d*)vh'), (m) => '${(double.parse(m.group(1)!) / 100 * _viewportHeight).round()}px');
    value = value.replaceAllMapped(RegExp(r'(\d+\.?\d*)rem'), (m) => '${(double.parse(m.group(1)!) * 14).round()}px');
    return value;
  }

  bool _selectorMatches(dom.Element element, String selector) {
    if (selector == '*' || selector == 'body') return true;
    if (selector == element.localName) return true;
    if (selector.startsWith('.')) return element.classes.contains(selector.substring(1));
    if (selector.startsWith('#')) return element.attributes['id'] == selector.substring(1);
    return _matchCompoundSelector(element, selector);
  }

  bool _matchCompoundSelector(dom.Element element, String selector) {
    return selector.split(RegExp(r'(?=[.#\[])')).every((part) {
      if (part.isEmpty) return true;
      if (part.startsWith('.')) return element.classes.contains(part.substring(1));
      if (part.startsWith('#')) return element.attributes['id'] == part.substring(1);
      return part == element.localName;
    });
  }
}

// ======================================================================
// 数据模型
// ======================================================================
class _CssRule {
  final String selector;
  final Map<String, String> properties;
  final int specificity;
  final CssSource source;
  final bool isActive;
  _CssRule({required this.selector, required this.properties, required this.specificity, required this.source, this.isActive = false});
}

class _MediaQuery {
  final String condition;
  final CssSource source;
  final List<_CssRule> rules = [];
  _MediaQuery({required this.condition, required this.source});
  
  bool matches(double screenWidth, double screenHeight, double pixelRatio) {
    if (condition.contains('max-width')) {
      final m = RegExp(r'max-width:\s*(\d+)px').firstMatch(condition);
      if (m != null) return screenWidth <= double.parse(m.group(1)!);
    }
    if (condition.contains('min-width')) {
      final m = RegExp(r'min-width:\s*(\d+)px').firstMatch(condition);
      if (m != null) return screenWidth >= double.parse(m.group(1)!);
    }
    if (condition.contains('orientation')) {
      if (condition.contains('landscape')) return screenWidth > screenHeight;
      if (condition.contains('portrait')) return screenWidth <= screenHeight;
    }
    return false;
  }
}

enum CssSource { userAgent, external, styleTag, inline }

class _FormData extends ChangeNotifier {
  final String method;
  final String action;
  final Map<String, String> values = {};
  _FormData({required this.method, required this.action});
  void setValue(String name, String value) { values[name] = value; notifyListeners(); }
}

// ======================================================================
// 主页面
// ======================================================================
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;
  @override State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _urlController = TextEditingController();
  String _htmlContent = '''
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      * { margin:0; padding:0; box-sizing:border-box; }
      body { font-family:-apple-system,sans-serif; line-height:1.5; }
      .container { display:flex; flex-direction:column; gap:16px; padding:16px; max-width:480px; margin:0 auto; }
      .flex-row { display:flex; flex-wrap:wrap; gap:10px; }
      .grid-2 { display:grid; grid-template-columns:1fr 1fr; gap:12px; }
      .card { background:white; border-radius:8px; padding:16px; box-shadow:0 2px 8px rgba(0,0,0,0.1); }
      .btn { display:inline-block; padding:12px 20px; min-height:44px; font-size:16px; border-radius:8px; background:#007aff; color:white; border:none; }
      img { max-width:100%; height:auto; }
      a { text-decoration:none; color:#007aff; }
    </style>
    <div class="container">
      <h1>移动端演示</h1>
      <div class="flex-row">
        <div class="card">Flex 1</div>
        <div class="card">Flex 2</div>
      </div>
      <div class="grid-2">
        <div class="card">Grid 1</div>
        <div class="card">Grid 2</div>
      </div>
      <form method="get" action="/search">
        <div class="flex-row">
          <input type="text" name="q" placeholder="搜索..." style="flex:1;">
          <button type="submit" class="btn">搜索</button>
        </div>
      </form>
    </div>
  ''';
  
  bool _isLoading = false;
  String _currentUrl = '';
  final Map<int, _FormData> _formRegistry = {};
  late _MobileCssParser cssParser;
  http.Client? _httpClient;

  @override
  void initState() {
    super.initState();
    cssParser = _MobileCssParser();
    _httpClient = http.Client();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeCssParser());
  }

  @override
  void dispose() {
    _httpClient?.close();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _initializeCssParser() async {
    final size = MediaQuery.of(context).size;
    cssParser.setViewport(width: size.width, height: size.height, pixelRatio: MediaQuery.of(context).devicePixelRatio);
    await cssParser.parseFromHtml(_htmlContent, client: _httpClient, screenWidth: size.width);
    if (mounted) setState(() {});
  }

  Future<void> _updateCssParser(String html, String baseUrl) async {
    cssParser.setBaseUrl(baseUrl);
    final size = MediaQuery.of(context).size;
    cssParser.setViewport(width: size.width, height: size.height);
    await cssParser.parseFromHtml(html, client: _httpClient, screenWidth: size.width);
    if (mounted) setState(() {});
  }

  _FormData? _getFormDataForElement(dom.Element element) {
    dom.Node? node = element.parent;
    while (node != null) {
      if (node is dom.Element && node.localName == 'form') {
        return _formRegistry.putIfAbsent(node.hashCode, () => _FormData(
          method: node.attributes['method']?.toLowerCase() ?? 'get',
          action: node.attributes['action'] ?? '',
        ));
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
    final lastSlash = uri.path.lastIndexOf('/');
    final basePath = lastSlash > 0 ? uri.path.substring(0, lastSlash) : '';
    return '${uri.scheme}://${uri.host}$basePath/$url';
  }

  Future<void> _fetchWebContent(String url) async {
    if (url.isEmpty) return;
    final fullUrl = _resolveUrl(url);
    setState(() { _isLoading = true; _currentUrl = fullUrl; _urlController.text = fullUrl; _formRegistry.clear(); });
    try {
      final response = await http.get(Uri.parse(fullUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15'
      }).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        setState(() => _htmlContent = response.body);
        await _updateCssParser(response.body, fullUrl);
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
          'Content-Type': 'application/x-www-form-urlencoded',
        }, body: data).timeout(const Duration(seconds: 10));
      } else {
        final qs = data.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');
        response = await http.get(Uri.parse(qs.isNotEmpty ? '$fullUrl?$qs' : fullUrl)).timeout(const Duration(seconds: 10));
      }
      setState(() { _currentUrl = fullUrl; _urlController.text = fullUrl; _htmlContent = response.body; });
      await _updateCssParser(response.body, fullUrl);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('出错: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==================================================================
  // Widget构建
  // ==================================================================
  Widget? _buildCustomWidget(dom.Element element) {
    final tag = element.localName;
    if (tag == 'input') return _buildHtmlInput(element);
    if (tag == 'button') return _buildHtmlButton(element);
    if (tag == 'select') return _buildHtmlSelect(element);
    if (tag == 'textarea') return _buildHtmlTextarea(element);
    if (tag == 'option') return const SizedBox.shrink();
    if (tag == 'style' || tag == 'meta' || tag == 'link' || tag == 'script' || tag == 'head') return const SizedBox.shrink();
    
    final styles = cssParser.getComputedStyle(element);
    final display = styles['display'];
    
    if (display == 'flex' || display == 'inline-flex') return _buildFlexLayout(element, styles);
    if (display == 'grid' || display == 'inline-grid') return _buildGridLayout(element, styles);
    if (tag == 'img') return _buildImageWidget(element, styles);
    if (tag == 'a') return _buildLinkWidget(element, styles);
    
    return _buildStyledWidget(element, styles);
  }

  Widget _buildFlexLayout(dom.Element element, Map<String, String> styles) {
    final direction = styles['flex-direction'] == 'column' ? Axis.vertical : Axis.horizontal;
    final wrap = styles['flex-wrap'] == 'wrap';
    final gap = _parsePx(styles['gap']);
    
    return Container(
      margin: _parseEdgeInsets(styles['margin']),
      padding: _parseEdgeInsets(styles['padding']),
      decoration: BoxDecoration(
        color: _parseColor(styles['background-color']),
        borderRadius: _parseBorderRadius(styles['border-radius']),
        boxShadow: _parseBoxShadow(styles['box-shadow']),
      ),
      constraints: _parsePx(styles['max-width']) != null ? BoxConstraints(maxWidth: _parsePx(styles['max-width'])!) : null,
      child: wrap
          ? Wrap(spacing: gap ?? 8, runSpacing: gap ?? 8, children: element.children.map((c) => HtmlWidget(c.outerHtml, customWidgetBuilder: _buildCustomWidget)).toList())
          : Flex(
              direction: direction,
              mainAxisAlignment: _parseMainAxisAlignment(styles['justify-content']),
              crossAxisAlignment: _parseCrossAxisAlignment(styles['align-items']),
              children: _wrapWithGap(element.children.map((c) => HtmlWidget(c.outerHtml, customWidgetBuilder: _buildCustomWidget)).toList(), gap, direction),
            ),
    );
  }

  Widget _buildGridLayout(dom.Element element, Map<String, String> styles) {
    final cols = styles['grid-template-columns']?.split(' ').where((s) => s.trim().isNotEmpty).length ?? 1;
    final gap = _parsePx(styles['gap']);
    final padding = _parseEdgeInsets(styles['padding']);
    
    return Container(
      margin: _parseEdgeInsets(styles['margin']),
      padding: padding,
      decoration: BoxDecoration(
        color: _parseColor(styles['background-color']),
        borderRadius: _parseBorderRadius(styles['border-radius']),
        boxShadow: _parseBoxShadow(styles['box-shadow']),
      ),
      child: LayoutBuilder(builder: (ctx, constraints) {
        final itemWidth = (constraints.maxWidth - padding.horizontal - (cols - 1) * (gap ?? 8)) / cols;
        return Wrap(
          spacing: gap ?? 8, runSpacing: gap ?? 8,
          children: element.children.map((c) => SizedBox(width: itemWidth, child: HtmlWidget(c.outerHtml, customWidgetBuilder: _buildCustomWidget))).toList(),
        );
      }),
    );
  }

  Widget _buildImageWidget(dom.Element element, Map<String, String> styles) {
    final src = element.attributes['src'] ?? '';
    return Container(
      margin: _parseEdgeInsets(styles['margin']),
      child: src.isNotEmpty
          ? ClipRRect(borderRadius: _parseBorderRadius(styles['border-radius']) ?? BorderRadius.zero, child: Image.network(src, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Container(height: 200, color: Colors.grey[300], child: const Icon(Icons.broken_image))))
          : Container(height: 200, color: Colors.grey[300], child: const Center(child: Text('图片'))),
    );
  }

  Widget _buildLinkWidget(dom.Element element, Map<String, String> styles) {
    final href = element.attributes['href'] ?? '';
    return GestureDetector(
      onTap: () { if (href.isNotEmpty) _fetchWebContent(_resolveUrl(href)); },
      child: Container(
        margin: _parseEdgeInsets(styles['margin']),
        padding: _parseEdgeInsets(styles['padding']),
        constraints: BoxConstraints(minHeight: _parsePx(styles['min-height']) ?? 44),
        child: HtmlWidget(element.outerHtml, customWidgetBuilder: _buildCustomWidget, textStyle: TextStyle(color: _parseColor(styles['color']) ?? const Color(0xFF007AFF))),
      ),
    );
  }

  Widget? _buildStyledWidget(dom.Element element, Map<String, String> styles) {
    final bgColor = _parseColor(styles['background-color']);
    final padding = _parseEdgeInsets(styles['padding']);
    final margin = _parseEdgeInsets(styles['margin']);
    final borderRadius = _parseBorderRadius(styles['border-radius']);
    
    if (bgColor != null || padding != EdgeInsets.zero || margin != EdgeInsets.zero || borderRadius != null) {
      return Container(
        margin: margin, padding: padding,
        decoration: BoxDecoration(color: bgColor, borderRadius: borderRadius, boxShadow: _parseBoxShadow(styles['box-shadow'])),
        child: HtmlWidget(element.outerHtml, customWidgetBuilder: _buildCustomWidget),
      );
    }
    return null;
  }

  // 表单控件
  Widget? _buildHtmlInput(dom.Element element) {
    final type = element.attributes['type']?.toLowerCase() ?? 'text';
    final name = element.attributes['name'] ?? '';
    final value = element.attributes['value'] ?? '';
    final placeholder = element.attributes['placeholder'] ?? '';
    final formData = _getFormDataForElement(element);
    return _InputWrapper(type: type, placeholder: placeholder, value: value, name: name, formData: formData, onSubmit: formData != null ? () => _submitForm(formData) : null);
  }

  Widget? _buildHtmlButton(dom.Element element) {
    final type = element.attributes['type']?.toLowerCase() ?? 'button';
    final formData = _getFormDataForElement(element);
    return _FormButtonWrapper(type: type, text: element.innerHtml, formData: formData, onSubmit: formData != null ? () => _submitForm(formData) : null);
  }

  Widget? _buildHtmlSelect(dom.Element element) {
    final formData = _getFormDataForElement(element);
    final items = element.getElementsByTagName('option').map((o) => MapEntry(o.text.trim(), o.attributes['value'] ?? o.text.trim())).toList();
    return _SelectWrapper(items: items, name: element.attributes['name'] ?? '', formData: formData);
  }

  Widget? _buildHtmlTextarea(dom.Element element) {
    final formData = _getFormDataForElement(element);
    return _TextareaWrapper(name: element.attributes['name'] ?? '', placeholder: element.attributes['placeholder'] ?? '', value: element.text.trim(), formData: formData);
  }

  // 辅助方法
  List<Widget> _wrapWithGap(List<Widget> children, double? gap, Axis direction) {
    if (gap == null || children.isEmpty) return children;
    return List.generate(children.length * 2 - 1, (i) => i.isOdd ? SizedBox(width: direction == Axis.horizontal ? gap : 0, height: direction == Axis.vertical ? gap : 0) : children[i ~/ 2]);
  }

  double? _parsePx(String? value) {
    if (value == null) return null;
    final m = RegExp(r'([\d.]+)').firstMatch(value);
    return m != null ? double.tryParse(m.group(1)!) : null;
  }

  Color? _parseColor(String? value) {
    if (value == null) return null;
    if (value.startsWith('#')) {
      final hex = value.substring(1);
      if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
      if (hex.length == 3) return Color(int.parse('FF${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}', radix: 16));
    }
    return null;
  }

  EdgeInsets _parseEdgeInsets(String? value) {
    if (value == null || value == '0') return EdgeInsets.zero;
    final parts = value.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.length == 1) return EdgeInsets.all(_parsePx(parts[0]) ?? 0);
    if (parts.length == 2) return EdgeInsets.symmetric(vertical: _parsePx(parts[0]) ?? 0, horizontal: _parsePx(parts[1]) ?? 0);
    if (parts.length == 4) return EdgeInsets.fromLTRB(_parsePx(parts[3]) ?? 0, _parsePx(parts[0]) ?? 0, _parsePx(parts[1]) ?? 0, _parsePx(parts[2]) ?? 0);
    return EdgeInsets.all(_parsePx(value) ?? 0);
  }

  BorderRadius? _parseBorderRadius(String? value) {
    final r = _parsePx(value);
    return r != null && r > 0 ? BorderRadius.circular(r) : null;
  }

  List<BoxShadow>? _parseBoxShadow(String? value) {
    if (value == null || value == 'none') return null;
    final m = RegExp(r'([\d.]+)px\s+([\d.]+)px\s+([\d.]+)px\s+rgba?\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)').firstMatch(value);
    if (m != null) {
      return [BoxShadow(offset: Offset(double.parse(m.group(1)!), double.parse(m.group(2)!)), blurRadius: double.parse(m.group(3)!), color: Color.fromRGBO(int.parse(m.group(4)!), int.parse(m.group(5)!), int.parse(m.group(6)!), double.parse(m.group(7)!)))];
    }
    return null;
  }

  MainAxisAlignment _parseMainAxisAlignment(String? value) {
    switch (value) {
      case 'center': return MainAxisAlignment.center;
      case 'flex-end': return MainAxisAlignment.end;
      case 'space-between': return MainAxisAlignment.spaceBetween;
      case 'space-around': return MainAxisAlignment.spaceAround;
      case 'space-evenly': return MainAxisAlignment.spaceEvenly;
      default: return MainAxisAlignment.start;
    }
  }

  CrossAxisAlignment _parseCrossAxisAlignment(String? value) {
    switch (value) {
      case 'center': return CrossAxisAlignment.center;
      case 'flex-end': return CrossAxisAlignment.end;
      case 'stretch': return CrossAxisAlignment.stretch;
      case 'baseline': return CrossAxisAlignment.baseline;
      default: return CrossAxisAlignment.center;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), backgroundColor: Theme.of(context).colorScheme.inversePrimary),
      body: Column(children: [
        Container(padding: const EdgeInsets.all(8), child: Row(children: [
          Expanded(child: TextField(controller: _urlController, onSubmitted: _fetchWebContent, decoration: InputDecoration(hintText: '输入网址...', contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)), filled: true, fillColor: Colors.grey[100]))),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: _isLoading ? null : () => _fetchWebContent(_urlController.text), child: _isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('前往')),
        ])),
        if (_isLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(12), child: HtmlWidget(_htmlContent, onTapUrl: (url) { _fetchWebContent(url); return true; }, customWidgetBuilder: _buildCustomWidget, textStyle: const TextStyle(fontSize: 14, height: 1.5)))),
        Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), color: Colors.grey[100], child: Text(_currentUrl.isNotEmpty ? _currentUrl : '就绪', style: TextStyle(fontSize: 11, color: Colors.grey[600]), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

// ======================================================================
// 表单组件
// ======================================================================
class _InputWrapper extends StatefulWidget {
  final String type, placeholder, value, name;
  final _FormData? formData;
  final VoidCallback? onSubmit;
  const _InputWrapper({required this.type, required this.placeholder, required this.value, required this.name, this.formData, this.onSubmit});
  @override State<_InputWrapper> createState() => _InputWrapperState();
}

class _InputWrapperState extends State<_InputWrapper> {
  late TextEditingController _controller;
  bool _checked = false;

  @override
  void initState() {
