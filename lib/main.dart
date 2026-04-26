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
// 增强版CSS解析器 - 完整移动端支持
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
      'margin': '0',
      'padding': '0',
      'box-sizing': 'border-box',
      '-webkit-tap-highlight-color': 'transparent',
    },
    'html': {
      'font-size': '14px',
      'scroll-behavior': 'smooth',
    },
    'body': {
      'font-family': '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif',
      'line-height': '1.5',
      'margin': '0',
      'padding': '0',
    },
    'div': {'display': 'block'},
    'span': {'display': 'inline'},
    'p': {'display': 'block', 'margin': '0 0 16px 0'},
    'h1': {'display': 'block', 'font-size': '2em', 'font-weight': 'bold'},
    'h2': {'display': 'block', 'font-size': '1.5em', 'font-weight': 'bold'},
    'h3': {'display': 'block', 'font-size': '1.17em', 'font-weight': 'bold'},
    'a': {
      'text-decoration': 'none',
      'color': '#007aff',
      '-webkit-touch-callout': 'none',
    },
    'img': {
      'max-width': '100%',
      'height': 'auto',
      'display': 'inline-block',
    },
    'video': {
      'max-width': '100%',
      'height': 'auto',
    },
    'button': {
      'display': 'inline-block',
      'min-height': '44px',
      'min-width': '44px',
      'padding': '12px 20px',
      'font-size': '16px',
      'border-radius': '8px',
      'border': 'none',
      '-webkit-appearance': 'none',
    },
    'input': {
      'display': 'inline-block',
      'min-height': '44px',
      'padding': '8px 12px',
      'font-size': '16px',
      '-webkit-appearance': 'none',
    },
    'textarea': {
      'display': 'inline-block',
      'min-height': '44px',
      'padding': '8px 12px',
      'font-size': '16px',
    },
    'select': {
      'display': 'inline-block',
      'min-height': '44px',
      'font-size': '16px',
    },
  };

  final List<_MediaQuery> _mediaQueries = [];

  void clear() {
    _rules.clear();
    _mediaQueries.clear();
    _styleCache.clear();
  }

  void setBaseUrl(String url) {
    _baseUrl = url;
  }

  void setViewport({double width = 375, double height = 812, double pixelRatio = 2.0}) {
    _viewportWidth = width;
    _viewportHeight = height;
    _devicePixelRatio = pixelRatio;
  }

  void parseViewportMeta(String html) {
    final viewportRegex = RegExp(
      r'<meta[^>]+name="viewport"[^>]+content="([^"]*)"',
      caseSensitive: false,
    );
    final match = viewportRegex.firstMatch(html);
    if (match != null) {
      final content = match.group(1) ?? '';
      _parseViewportContent(content);
    }
  }

  void _parseViewportContent(String content) {
    final parts = content.split(',');
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.startsWith('width=')) {
        final width = trimmed.substring(6);
        if (width == 'device-width') {
          // 保持设备宽度
        } else {
          _viewportWidth = double.tryParse(width) ?? 375;
        }
      }
      // initial-scale 和 maximum-scale 记录但不强制处理
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
      final specificity = selector == '*' ? 0 : 10;
      _rules.add(_CssRule(
        selector: selector,
        properties: Map.from(properties),
        specificity: specificity,
        source: CssSource.userAgent,
      ));
    });
  }

  Future<void> _parseStyleTags(String html) async {
    final styleRegex = RegExp(r'<style[^>]*>(.*?)</style>', dotAll: true);
    final matches = styleRegex.allMatches(html);

    for (final match in matches) {
      final cssText = match.group(1)?.trim() ?? '';
      _parseCssText(cssText, CssSource.styleTag);
    }
  }

  Future<void> _fetchExternalStylesheets(String html, http.Client client) async {
    final document = html_parser.parse(html);
    final linkElements = document.querySelectorAll('link[rel="stylesheet"]');
    
    for (final link in linkElements) {
      final href = link.attributes['href'];
      if (href == null || href.isEmpty) continue;
      
      try {
        final cssUrl = _resolveUrl(href);
        final response = await client.get(
          Uri.parse(cssUrl),
          headers: {'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15'},
        ).timeout(const Duration(seconds: 5));
        
        if (response.statusCode == 200) {
          _parseCssText(response.body, CssSource.external);
        }
      } catch (e) {
        debugPrint('无法加载外部CSS: $href - $e');
      }
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
    
    final blockRegex = RegExp(r'([^{]+)\{([^}]*)\}');
    final blocks = blockRegex.allMatches(normalCss);

    for (final block in blocks) {
      final selectorsStr = block.group(1)?.trim() ?? '';
      final propertiesStr = block.group(2)?.trim() ?? '';
      
      if (propertiesStr.isEmpty) continue;
      
      final properties = _parseProperties(propertiesStr);
      if (properties.isEmpty) continue;
      
      final isActive = selectorsStr.contains(':active');
      final isHover = selectorsStr.contains(':hover');
      
      String cleanSelector = selectorsStr.replaceAll(RegExp(r':(active|hover|focus|visited)'), '');
      
      final selectors = cleanSelector.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
      
      for (final selector in selectors) {
        final specificity = _calculateSpecificity(selector);
        _rules.add(_CssRule(
          selector: selector,
          properties: Map.from(properties),
          specificity: specificity,
          source: source,
          isActive: isActive,
          isHover: isHover,
        ));
      }
    }
  }

  void _extractMediaQueries(String cssText) {
    final mediaRegex = RegExp(r'@media\s+([^{]+)\{([^}]*)\}', dotAll: true);
    final matches = mediaRegex.allMatches(cssText);
    
    for (final match in matches) {
      final condition = match.group(1)?.trim() ?? '';
      final rulesCss = match.group(2)?.trim() ?? '';
      
      final query = _MediaQuery(condition: condition, source: CssSource.styleTag);
      
      final blockRegex = RegExp(r'([^{]+)\{([^}]*)\}');
      final blocks = blockRegex.allMatches(rulesCss);
      
      for (final block in blocks) {
        final selector = block.group(1)?.trim() ?? '';
        final propertiesStr = block.group(2)?.trim() ?? '';
        final properties = _parseProperties(propertiesStr);
        
        if (selector.isNotEmpty && properties.isNotEmpty) {
          query.rules.add(_CssRule(
            selector: selector,
            properties: properties,
            specificity: _calculateSpecificity(selector),
            source: CssSource.styleTag,
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
    final propRegex = RegExp(r'([\w-]+)\s*:\s*([^;]+);?');
    final matches = propRegex.allMatches(propertiesStr);

    for (final match in matches) {
      final key = match.group(1)?.trim().toLowerCase() ?? '';
      final value = match.group(2)?.trim() ?? '';
      if (key.isNotEmpty && value.isNotEmpty) {
        props[key] = value;
      }
    }
    return props;
  }

  int _calculateSpecificity(String selector) {
    int score = 0;
    score += '#'.allMatches(selector).length * 10000;
    score += '.'.allMatches(selector).length * 100;
    score += '['.allMatches(selector).length * 100;
    score += ':'.allMatches(selector).length * 10;
    if (RegExp(r'^[a-zA-Z]+').hasMatch(selector)) {
      score += 1;
    }
    return score;
  }

  Map<String, String> getComputedStyle(dom.Element element) {
    if (_styleCache.containsKey(element)) {
      return Map.from(_styleCache[element]!);
    }
    
    final styles = <String, String>{};
    
    if (_userAgentStyles.containsKey('*')) {
      styles.addAll(_userAgentStyles['*']!);
    }
    
    final tagName = element.localName?.toLowerCase() ?? '';
    if (_userAgentStyles.containsKey(tagName)) {
      styles.addAll(_userAgentStyles[tagName]!);
    }
    
    for (final rule in _rules) {
      if (_selectorMatches(element, rule.selector)) {
        styles.addAll(rule.properties);
      }
    }
    
    final inlineStyle = element.attributes['style'];
    if (inlineStyle != null && inlineStyle.isNotEmpty) {
      styles.addAll(_parseProperties(inlineStyle));
    }
    
    styles.forEach((key, value) {
      styles[key] = _resolveCssValue(value);
    });
    
    _styleCache[element] = Map.from(styles);
    return styles;
  }

  String _resolveCssValue(String value) {
    if (value.contains('calc(')) {
      value = value.replaceAllMapped(RegExp(r'calc\((.*?)\)'), (match) {
        return match.group(1) ?? '';
      });
    }
    
    value = value.replaceAllMapped(RegExp(r'(\d+\.?\d*)vw'), (match) {
      final num = double.parse(match.group(1)!);
      return '${(num / 100 * _viewportWidth).round()}px';
    });
    
    value = value.replaceAllMapped(RegExp(r'(\d+\.?\d*)vh'), (match) {
      final num = double.parse(match.group(1)!);
      return '${(num / 100 * _viewportHeight).round()}px';
    });
    
    value = value.replaceAllMapped(RegExp(r'(\d+\.?\d*)rem'), (match) {
      final num = double.parse(match.group(1)!);
      return '${(num * 14).round()}px';
    });
    
    return value;
  }

  bool _selectorMatches(dom.Element element, String selector) {
    if (selector == '*' || selector == 'body') return true;
    if (selector == element.localName) return true;
    
    if (selector.startsWith('.')) {
      return element.classes.contains(selector.substring(1));
    }
    
    if (selector.startsWith('#')) {
      return element.attributes['id'] == selector.substring(1);
    }
    
    if (selector.startsWith('[')) {
      final attrMatch = RegExp(r'\[([\w-]+)(?:="([^"]*)")?\]').firstMatch(selector);
      if (attrMatch != null) {
        final attrName = attrMatch.group(1) ?? '';
        final attrValue = attrMatch.group(2);
        if (attrValue != null) {
          return element.attributes[attrName] == attrValue;
        }
        return element.attributes.containsKey(attrName);
      }
    }
    
    return _matchCompoundSelector(element, selector);
  }

  bool _matchCompoundSelector(dom.Element element, String selector) {
    final parts = selector.split(RegExp(r'(?=[.#\[])'));
    return parts.every((part) {
      if (part.isEmpty) return true;
      if (part.startsWith('.')) return element.classes.contains(part.substring(1));
      if (part.startsWith('#')) return element.attributes['id'] == part.substring(1);
      if (part.startsWith('[')) {
        final attrMatch = RegExp(r'\[([\w-]+)(?:="([^"]*)")?\]').firstMatch(part);
        if (attrMatch != null) {
          final attrName = attrMatch.group(1) ?? '';
          final attrValue = attrMatch.group(2);
          return attrValue != null
              ? element.attributes[attrName] == attrValue
              : element.attributes.containsKey(attrName);
        }
      }
      return part == element.localName;
    });
  }
}

class _CssRule {
  final String selector;
  final Map<String, String> properties;
  final int specificity;
  final CssSource source;
  final bool isActive;
  final bool isHover;

  _CssRule({
    required this.selector,
    required this.properties,
    required this.specificity,
    required this.source,
    this.isActive = false,
    this.isHover = false,
  });
}

class _MediaQuery {
  final String condition;
  final CssSource source;
  final List<_CssRule> rules = [];

  _MediaQuery({
    required this.condition,
    required this.source,
  });

  bool matches(double screenWidth, double screenHeight, double pixelRatio) {
    if (condition.contains('max-width')) {
      final match = RegExp(r'max-width:\s*(\d+)px').firstMatch(condition);
      if (match != null) {
        return screenWidth <= double.parse(match.group(1)!);
      }
    }
    if (condition.contains('min-width')) {
      final match = RegExp(r'min-width:\s*(\d+)px').firstMatch(condition);
      if (match != null) {
        return screenWidth >= double.parse(match.group(1)!);
      }
    }
    if (condition.contains('orientation')) {
      if (condition.contains('landscape')) return screenWidth > screenHeight;
      if (condition.contains('portrait')) return screenWidth <= screenHeight;
    }
    if (condition.contains('min-resolution') || condition.contains('min-device-pixel-ratio')) {
      return pixelRatio >= 2;
    }
    return false;
  }
}

enum CssSource {
  userAgent,
  external,
  styleTag,
  inline,
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
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
    <style>
      * { margin: 0; padding: 0; box-sizing: border-box; }
      body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; line-height: 1.5; }
      
      .container { display: flex; flex-direction: column; gap: 16px; padding: 16px; max-width: 480px; margin: 0 auto; }
      .flex-row { display: flex; flex-wrap: wrap; gap: 10px; }
      .grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
      
      .card { background: white; border-radius: 8px; padding: 16px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
      .btn { display: inline-block; padding: 12px 20px; min-height: 44px; font-size: 16px; border-radius: 8px; background: #007aff; color: white; border: none; }
      .btn:active { opacity: 0.7; transform: scale(0.98); }
      
      img { max-width: 100%; height: auto; }
      a { text-decoration: none; color: #007aff; }
      
      @media (max-width: 375px) {
        .container { padding: 10px; }
      }
    </style>
    
    <div class="container">
      <h1 style="font-size: 5vw;">移动端演示</h1>
      <p style="font-size: 0.875rem;">响应式布局测试</p>
      
      <div class="flex-row">
        <div class="card">Flex 项目 1</div>
        <div class="card">Flex 项目 2</div>
      </div>
      
      <div class="grid-2">
        <div class="card">网格 1</div>
        <div class="card">网格 2</div>
        <div class="card">网格 3</div>
        <div class="card">网格 4</div>
      </div>
      
      <img src="https://via.placeholder.com/480x200" alt="示例图片">
      
      <form method="get" action="/search">
        <div class="flex-row">
          <input type="text" name="q" placeholder="搜索..." style="flex: 1; min-height: 44px; padding: 8px 12px; font-size: 16px;">
          <button type="submit" class="btn">搜索</button>
        </div>
      </form>
      
      <a href="#" class="btn">了解更多</a>
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
    _initializeCssParser();
  }

  @override
  void dispose() {
    _httpClient?.close();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _initializeCssParser() async {
    final screenSize = MediaQuery.of(context).size;
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    
    cssParser.setViewport(
      width: screenSize.width,
      height: screenSize.height,
      pixelRatio: pixelRatio,
    );
    
    await cssParser.parseFromHtml(_htmlContent, client: _httpClient, screenWidth: screenSize.width);
    if (mounted) setState(() {});
  }

  Future<void> _updateCssParser(String html, String baseUrl) async {
    cssParser.setBaseUrl(baseUrl);
    
    final screenSize = MediaQuery.of(context).size;
    cssParser.setViewport(width: screenSize.width, height: screenSize.height);
    
    await cssParser.parseFromHtml(html, client: _httpClient, screenWidth: screenSize.width);
    if (mounted) setState(() {});
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
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15'
      }).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final htmlContent = _fixEncoding(response);
        setState(() {
          _htmlContent = htmlContent;
        });
        await _updateCssParser(htmlContent, fullUrl);
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
          'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)',
          'Content-Type': 'application/x-www-form-urlencoded',
        }, body: data).timeout(const Duration(seconds: 10));
      } else {
        final queryString = data.entries
            .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
            .join('&');
        final url = queryString.isNotEmpty ? '$fullUrl?$queryString' : fullUrl;
        response = await http.get(Uri.parse(url), headers: {
          'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)'
        }).timeout(const Duration(seconds: 10));
      }
      final htmlContent = _fixEncoding(response);
      setState(() {
        _currentUrl = fullUrl;
        _urlController.text = fullUrl;
        _htmlContent = htmlContent;
      });
      await _updateCssParser(htmlContent, fullUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('表单提交出错: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==================================================================
  // 核心：CSS布局拦截 + 表单控件拦截
  // ==================================================================
  Widget? _buildCustomWidget(dom.Element element) {
    final tag = element.localName;
    
    if (tag == 'input') return _buildHtmlInput(element);
    if (tag == 'button') return _buildHtmlButton(element);
    if (tag == 'select') return _buildHtmlSelect(element);
    if (tag == 'textarea') return _buildHtmlTextarea(element);
    if (tag == 'option') return const SizedBox.shrink();
    if (tag == 'style' || tag == 'meta' || tag == 'link' || tag == 'script' || tag == 'head') {
      return const SizedBox.shrink();
    }
    
    final computedStyle = cssParser.getComputedStyle(element);
    
    final display = computedStyle['display'];
    
    if (display == 'flex' || display == 'inline-flex') {
      return _buildFlexLayout(element, computedStyle);
    }
    if (display == 'grid' || display == 'inline-grid') {
      return _buildGridLayout(element, computedStyle);
    }
    
    if (tag == 'img') {
      return _buildImageWidget(element, computedStyle);
    }
    
    if (tag == 'a') {
      return _buildLinkWidget(element, computedStyle);
    }
    
    return _buildStyledWidget(element, computedStyle);
  }

  // ==================================================================
  // 布局构建器
  // ==================================================================
  Widget _buildFlexLayout(dom.Element element, Map<String, String> styles) {
    final direction = styles['flex-direction'] == 'column' ? Axis.vertical : Axis.horizontal;
    final wrap = styles['flex-wrap'] == 'wrap';
    final mainAxisAlignment = _parseMainAxisAlignment(styles['justify-content']);
    final crossAxisAlignment = _parseCrossAxisAlignment(styles['align-items']);
    
    double? gap = _parsePxValue(styles['gap']);
    
    final padding = _parseEdgeInsets(styles['padding']);
    final margin = _parseEdgeInsets(styles['margin']);
    final borderRadius = _parseBorderRadius(styles['border-radius']);
    
    final bgColor = _parseColor(styles['background-color']);
    final boxShadow = _parseBoxShadow(styles['box-shadow']);
    final maxWidth = _parsePxValue(styles['max-width']);
    
    final children = element.children
        .map((child) => HtmlWidget(
              child.outerHtml,
              customWidgetBuilder: _buildCustomWidget,
            ))
        .toList();

    Widget flexWidget;
    if (wrap) {
      flexWidget = Wrap(
        direction: direction == Axis.horizontal ? Axis.horizontal : Axis.vertical,
        spacing: gap ?? 8,
        runSpacing: gap ?? 8,
        children: children,
      );
    } else {
      flexWidget = Flex(
        direction: direction,
        mainAxisAlignment: mainAxisAlignment,
        crossAxisAlignment: crossAxisAlignment,
        children: _wrapWithGap(children, gap, direction),
      );
    }

    return Container(
      margin: margin,
      padding: padding,
      constraints: maxWidth != null ? BoxConstraints(maxWidth: maxWidth) : null,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: borderRadius,
        boxShadow: boxShadow,
      ),
      child: flexWidget,
    );
  }

  Widget _buildGridLayout(dom.Element element, Map<String, String> styles) {
    final columnsStr = styles['grid-template-columns'];
    final columnCount = columnsStr?.split(' ').where((s) => s.trim().isNotEmpty).length ?? 1;
    
    double? gap = _parsePxValue(styles['gap']);
    final padding = _parseEdgeInsets(styles['padding']);
    final margin = _parseEdgeInsets(styles['margin']);
    final borderRadius = _parseBorderRadius(styles['border-radius']);
    final bgColor = _parseColor(styles['background-color']);
    final boxShadow = _parseBoxShadow(styles['box-shadow']);
    final maxWidth = _parsePxValue(styles['max-width']);

    return Container(
      margin: margin,
      padding: padding,
      constraints: maxWidth != null ? BoxConstraints(maxWidth: maxWidth) : null,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: borderRadius,
        boxShadow: boxShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalGap = gap != null ? (columnCount - 1) * gap : 0;
          final itemWidth = (constraints.maxWidth - padding.horizontal - totalGap) / columnCount;
          
          return Wrap(
            spacing: gap ?? 8,
            runSpacing: gap ?? 8,
            children: element.children.map((child) {
              return SizedBox(
                width: itemWidth > 0 ? itemWidth : null,
                child: HtmlWidget(
                  child.outerHtml,
                  customWidgetBuilder: _buildCustomWidget,
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildImageWidget(dom.Element element, Map<String, String> styles) {
    final src = element.attributes['src'] ?? '';
    final alt = element.attributes['alt'] ?? '';
    final maxWidth = _parsePxValue(styles['max-width']);
    final borderRadius = _parseBorderRadius(styles['border-radius']);
    final margin = _parseEdgeInsets(styles['margin']);
    
    return Container(
      margin: margin,
      constraints: maxWidth != null ? BoxConstraints(maxWidth: maxWidth) : const BoxConstraints(maxWidth: double.infinity),
      child: src.isNotEmpty
          ? ClipRRect(
              borderRadius: borderRadius ?? BorderRadius.zero,
              child: Image.network(
                src,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) {
                  return Container(
                    height: 200,
                    color: Colors.grey[300],
                    child: const Center(child: Icon(Icons.broken_image)),
                  );
                },
              ),
            )
          : Container(
              height: 200,
              color: Colors.grey[300],
              child: Center(child: Text(alt.isNotEmpty ? alt : '图片')),
            ),
    );
  }

  Widget _buildLinkWidget(dom.Element element, Map<String, String> styles) {
    final href = element.attributes['href'] ?? '';
    final color = _parseColor(styles['color']) ?? const Color(0xFF007AFF);
    final padding = _parseEdgeInsets(styles['padding']);
    final margin = _parseEdgeInsets(styles['margin']);
    final minHeight = _parsePxValue(styles['min-height']) ?? 44;
    final minWidth = _parsePxValue(styles['min-width']) ?? 44;
    
    return Container(
      margin: margin,
      padding: padding,
      constraints: BoxConstraints(minHeight: minHeight, minWidth: minWidth),
      child: GestureDetector(
        onTap: () {
          if (href.isNotEmpty) {
            _fetchWebContent(_resolveUrl(href));
          }
        },
        child: HtmlWidget(
          element.outerHtml,
          customWidgetBuilder: _buildCustomWidget,
          textStyle: TextStyle(color: color),
        ),
      ),
    );
  }

  Widget? _buildStyledWidget(dom.Element element, Map<String, String> styles) {
    final bgColor = _parseColor(styles['background-color']);
    final padding = _parseEdgeInsets(styles['padding']);
    final margin = _parseEdgeInsets(styles['margin']);
    final borderRadius = _parseBorderRadius(styles['border-radius']);
    final boxShadow = _parseBoxShadow(styles['box-shadow']);
    final maxWidth = _parsePxValue(styles['max-width']);
    
    if (bgColor != null || padding != EdgeInsets.zero || margin != EdgeInsets.zero || borderRadius != null || maxWidth != null) {
      return Container(
