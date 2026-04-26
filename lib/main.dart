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
        // 移动端字体
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
  
  // 视口设置
  double _viewportWidth = 375; // 默认iPhone宽度
  double _viewportHeight = 812; // 默认iPhone高度
  double _devicePixelRatio = 2.0;
  
  // 浏览器默认样式表（完整移动端重置）
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
    'h1': {'display': 'block', 'font-size': '2em', 'font-weight': 'bold', 'margin': '0.67em 0'},
    'h2': {'display': 'block', 'font-size': '1.5em', 'font-weight': 'bold', 'margin': '0.83em 0'},
    'h3': {'display': 'block', 'font-size': '1.17em', 'font-weight': 'bold', 'margin': '1em 0'},
    'h4': {'display': 'block', 'font-size': '1em', 'font-weight': 'bold', 'margin': '1.33em 0'},
    'h5': {'display': 'block', 'font-size': '0.83em', 'font-weight': 'bold', 'margin': '1.67em 0'},
    'h6': {'display': 'block', 'font-size': '0.67em', 'font-weight': 'bold', 'margin': '2.33em 0'},
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
    'ul': {'display': 'block', 'margin': '16px 0', 'padding-left': '40px'},
    'ol': {'display': 'block', 'margin': '16px 0', 'padding-left': '40px'},
    'li': {'display': 'list-item'},
    'button': {
      'display': 'inline-block',
      'min-height': '44px',
      'min-width': '44px',
      'padding': '12px 20px',
      'font-size': '16px',
      'border-radius': '8px',
      'border': 'none',
      'cursor': 'pointer',
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
    'form': {'display': 'block'},
    'table': {'display': 'table', 'width': '100%', 'border-collapse': 'collapse'},
    'tr': {'display': 'table-row'},
    'td': {'display': 'table-cell', 'padding': '8px'},
    'th': {'display': 'table-cell', 'padding': '8px', 'font-weight': 'bold'},
    'hr': {'display': 'block', 'border': '1px solid #eee', 'margin': '16px 0'},
  };

  // 媒体查询存储
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

  // 从HTML的meta标签提取viewport
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
          // 使用设备宽度，这里用MediaQuery获取
          _viewportWidth = 375; // 默认
        } else {
          _viewportWidth = double.tryParse(width) ?? 375;
        }
      } else if (trimmed.startsWith('initial-scale=')) {
        final scale = double.tryParse(trimmed.substring(14)) ?? 1.0;
        // 根据缩放调整视口
      } else if (trimmed.startsWith('maximum-scale=')) {
        // 记录最大缩放
      }
    }
  }

  // 主解析入口
  Future<void> parseFromHtml(String html, {http.Client? client, double screenWidth = 375}) async {
    clear();
    
    // 1. 解析viewport
    parseViewportMeta(html);
    
    // 2. 应用用户代理样式
    _applyUserAgentStyles();
    
    // 3. 解析<style>标签
    await _parseStyleTags(html);
    
    // 4. 解析外部CSS
    if (client != null && _baseUrl.isNotEmpty) {
      await _fetchExternalStylesheets(html, client);
    }
    
    // 5. 应用媒体查询
    _applyMediaQueries(screenWidth);
    
    // 6. 按优先级排序
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
    // 移除注释
    final cleanCss = cssText.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    
    // 提取媒体查询
    _extractMediaQueries(cleanCss);
    
    // 移除媒体查询块，只解析普通CSS
    var normalCss = cleanCss.replaceAll(RegExp(r'@media[^{]+\{[^}]*\}', dotAll: true), '');
    
    // 匹配规则块
    final blockRegex = RegExp(r'([^{]+)\{([^}]*)\}');
    final blocks = blockRegex.allMatches(normalCss);

    for (final block in blocks) {
      final selectorsStr = block.group(1)?.trim() ?? '';
      final propertiesStr = block.group(2)?.trim() ?? '';
      
      if (propertiesStr.isEmpty) continue;
      
      final properties = _parseProperties(propertiesStr);
      if (properties.isEmpty) continue;
      
      // 处理激活态、悬停态等
      final isPseudoClass = selectorsStr.contains(':');
      final isActive = selectorsStr.contains(':active');
      final isHover = selectorsStr.contains(':hover');
      
      String cleanSelector = selectorsStr;
      if (isPseudoClass) {
        cleanSelector = selectorsStr.replaceAll(RegExp(r':(active|hover|focus|visited)'), '');
      }
      
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
      
      // 解析媒体查询内的规则
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
    
    // ID选择器
    score += '#'.allMatches(selector).length * 10000;
    
    // 类选择器、属性选择器、伪类
    score += '.'.allMatches(selector).length * 100;
    score += '['.allMatches(selector).length * 100;
    score += ':'.allMatches(selector).length * 10;
    
    // 元素选择器
    if (RegExp(r'^[a-zA-Z]+').hasMatch(selector)) {
      score += 1;
    }
    
    return score;
  }

  bool _matchesMediaQuery(String condition, double screenWidth) {
    // 解析常用媒体查询条件
    if (condition.contains('max-width')) {
      final match = RegExp(r'max-width:\s*(\d+)px').firstMatch(condition);
      if (match != null) {
        final maxWidth = double.parse(match.group(1)!);
        return screenWidth <= maxWidth;
      }
    }
    if (condition.contains('min-width')) {
      final match = RegExp(r'min-width:\s*(\d+)px').firstMatch(condition);
      if (match != null) {
        final minWidth = double.parse(match.group(1)!);
        return screenWidth >= minWidth;
      }
    }
    if (condition.contains('orientation')) {
      if (condition.contains('landscape')) {
        return screenWidth > _viewportHeight;
      }
      if (condition.contains('portrait')) {
        return screenWidth <= _viewportHeight;
      }
    }
    return false;
  }

  // 获取元素完整样式（合并所有来源）
  Map<String, String> getComputedStyle(dom.Element element) {
    if (_styleCache.containsKey(element)) {
      return Map.from(_styleCache[element]!);
    }
    
    final styles = <String, String>{};
    
    // 1. 应用用户代理样式
    if (_userAgentStyles.containsKey('*')) {
      styles.addAll(_userAgentStyles['*']!);
    }
    
    final tagName = element.localName?.toLowerCase() ?? '';
    if (_userAgentStyles.containsKey(tagName)) {
      styles.addAll(_userAgentStyles[tagName]!);
    }
    
    // 2. 应用CSS规则（按优先级）
    for (final rule in _rules) {
      if (_selectorMatches(element, rule.selector)) {
        styles.addAll(rule.properties);
      }
    }
    
    // 3. 内联样式（最高优先级）
    final inlineStyle = element.attributes['style'];
    if (inlineStyle != null && inlineStyle.isNotEmpty) {
      styles.addAll(_parseProperties(inlineStyle));
    }
    
    // 4. 处理calc()、vw、vh等单位
    styles.forEach((key, value) {
      styles[key] = _resolveCssValue(value);
    });
    
    _styleCache[element] = Map.from(styles);
    return styles;
  }

  String _resolveCssValue(String value) {
    // 处理 calc()
    if (value.contains('calc(')) {
      value = value.replaceAllMapped(RegExp(r'calc\((.*?)\)'), (match) {
        final expression = match.group(1) ?? '';
        return _evaluateCalc(expression);
      });
    }
    
    // 处理 vw
    value = value.replaceAllMapped(RegExp(r'(\d+\.?\d*)vw'), (match) {
      final num = double.parse(match.group(1)!);
      return '${(num / 100 * _viewportWidth).round()}px';
    });
    
    // 处理 vh
    value = value.replaceAllMapped(RegExp(r'(\d+\.?\d*)vh'), (match) {
      final num = double.parse(match.group(1)!);
      return '${(num / 100 * _viewportHeight).round()}px';
    });
    
    // 处理 rem (基准14px)
    value = value.replaceAllMapped(RegExp(r'(\d+\.?\d*)rem'), (match) {
      final num = double.parse(match.group(1)!);
      return '${(num * 14).round()}px';
    });
    
    return value;
  }

  String _evaluateCalc(String expression) {
    try {
      // 简单处理 calc(100% - 30px) 这类表达式
      expression = expression.replaceAll('%', '');
      expression = expression.replaceAll('px', '');
      // 这里可以做更复杂的计算
      return expression;
    } catch (e) {
      return '0';
    }
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

// CSS规则类
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
        .font-small { font-size: 13px; }
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
    // 获取屏幕尺寸用于媒体查询
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
    
    // 表单控件
    if (tag == 'input') return _buildHtmlInput(element);
    if (tag == 'button') return _buildHtmlButton(element);
    if (tag == 'select') return _buildHtmlSelect(element);
    if (tag == 'textarea') return _buildHtmlTextarea(element);
    if (tag == 'option') return const SizedBox.shrink();
    if (tag == 'style' || tag == 'meta' || tag == 'link' || tag == 'script' || tag == 'head') {
      return const SizedBox.shrink();
    }
    
    // 获取计算后的样式
    final computedStyle = cssParser.getComputedStyle(element);
    
    // 处理display属性
    final display = computedStyle['display'];
    
    if (display == 'flex' || display == 'inline-flex') {
      return _buildFlexLayout(element, computedStyle);
    }
    if (display == 'grid' || display == 'inline-grid') {
      return _buildGridLayout(element, computedStyle);
    }
    
    // 处理图片
    if (tag == 'img') {
      return _buildImageWidget(element, computedStyle);
    }
    
    // 处理链接
    if (tag == 'a') {
      return _buildLinkWidget(element, computedStyle);
    }
    
    // 应用通用样式
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
    
    // 解析间距
    double? gap = _parsePxValue(styles['gap']);
    if (gap == null) {
      // 兼容 row-gap 和 column-gap
      gap = _parsePxValue(styles['row-gap']) ?? _parsePxValue(styles['column-gap']);
    }
    
    // 解析边距和圆角
    final padding = _parseEdgeInsets(styles['padding']);
    final margin = _parseEdgeInsets(styles['margin']);
    final borderRadius = _parseBorderRadius(styles['border-radius']);
    
    // 解析背景
    final bgColor = _parseColor(styles['background-color']);
    final bgDecoration = _parseBackground(styles);
    
    // 解析阴影
    final boxShadow = _parseBoxShadow(styles['box-shadow']);
    
    // 解析最大宽度（响应式）
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
      width: styles['width'] != null ? double.tryParse(styles['width']!) : null,
      margin: margin,
      padding: padding,
      constraints: maxWidth != null ? BoxConstraints(maxWidth: maxWidth) : null,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: borderRadius,
        boxShadow: boxShadow,
        ...bgDecoration,
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
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        image: src.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(src),
                fit: BoxFit.contain,
                onError: (_, __) {},
              )
            : null,
      ),
      child: src.isEmpty
          ? Container(
              height: 200,
              color: Colors.grey[300],
              child: Center(child: Text(alt.isNotEmpty ? alt : '图片')),
            )
          : AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: borderRadius ?? BorderRadius.zero,
                child: Image.network(src, fit: BoxFit.contain, errorBuilder: (_, __, ___) {
                  return Container(color: Colors.grey[300], child: const Icon(Icons.broken_image));
                }),
              ),
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
          textStyle: TextStyle(color: color, decoration: styles['text-decoration'] == 'underline' ? TextDecoration.underline : null),
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
    final minHeight = _parsePxValue(styles['min-height']) ?? 44;
    
    if (bgColor != null || padding != EdgeInsets.zero || margin != EdgeInsets.zero || borderRadius != null || maxWidth != null) {
      return Container(
        margin: margin,
        padding: padding,
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? double.infinity,
          minHeight: minHeight,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: borderRadius,
          boxShadow: boxShadow,
        ),
        child: HtmlWidget(
          element.outerHtml,
          customWidgetBuilder: _buildCustomWidget,
        ),
      );
    }
    
    return null;
  }

  // ==================================================================
  // 表单控件构建器
  // ==================================================================
  Widget? _buildHtmlInput(dom.Element element) {
    final type = element.attributes['type']?.toLowerCase() ?? 'text';
    final name = element.attributes['name'] ?? '';
    final value = element.attributes['value'] ?? '';
    final placeholder = element.attributes['placeholder'] ?? '';
    final formData = _getFormDataForElement(element);
    final styles = cssParser.getComputedStyle(element);
    final minHeight = _parsePxValue(styles['min-height']) ?? 44;
    final fontSize = _parsePxValue(styles['font-size']) ?? 16;
    
    return Padding(
      padding: _parseEdgeInsets(styles['padding']),
      child: _InputWrapper(
        type: type,
        placeholder: placeholder,
        value: value,
        name: name,
        formData: formData,
        minHeight: minHeight,
        fontSize: fontSize,
        onSubmit: formData != null ? () => _submitForm(formData) : null,
      ),
    );
  }

  Widget? _buildHtmlButton(dom.Element element) {
    final type = element.attributes['type']?.toLowerCase() ?? 'button';
    final text = element.innerHtml;
    final formData = _getFormDataForElement(element);
    final styles = cssParser.getComputedStyle(element);
    final minHeight = _parsePxValue(styles['min-height']) ?? 44;
    
    return Padding(
      padding: _parseEdgeInsets(styles['padding']),
      child: SizedBox(
        height: minHeight,
        child: _FormButtonWrapper(
          type: type,
          text: text,
          formData: formData,
          onSubmit: formData != null ? () => _submitForm(formData) : null,
        ),
      ),
    );
  }

  Widget? _buildHtmlSelect(dom.Element element) {
    final name = element.attributes['name'] ?? '';
    final formData = _getFormDataForElement(element);
    final options = element.getElementsByTagName('option');
    final items = options
        .map((opt) => MapEntry(opt.text.trim(), opt.attributes['value'] ?? opt.text.trim()))
        .toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: _SelectWrapper(items: items, name: name, formData: formData),
    );
  }

  Widget? _buildHtmlTextarea(dom.Element element) {
    final name = element.attributes['name'] ?? '';
    final placeholder = element.attributes['placeholder'] ?? '';
    final value = element.text.trim();
    final formData = _getFormDataForElement(element);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: _TextareaWrapper(name: name, placeholder: placeholder, value: value, formData: formData),
    );
  }

  // ==================================================================
  // CSS属性解析器（增强版）
  // ==================================================================
  List<Widget> _wrapWithGap(List<Widget> children, double? gap, Axis direction) {
    if (gap == null || gap == 0 || children.isEmpty) return children;
    return List.generate(children.length * 2 - 1, (index) {
      if (index.isOdd) {
        return SizedBox(
          width: direction == Axis.horizontal ? gap : 0,
          height: direction == Axis.vertical ? gap : 0,
        );
      }
      return children[index ~/ 2];
    });
  }

  double? _parsePxValue(String? value) {
    if (value == null || value == 'auto' || value == 'none') return null;
    if (value == '0') return 0;
    
    // 处理 calc()
    if (value.contains('calc(')) {
      value = value.replaceAll('calc(', '').replaceAll(')', '');
    }
    
    // 提取数字
    final match = RegExp(r'(-?[\d.]+)').firstMatch(value);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
    return null;
  }

  Color? _parseColor(String? value) {
    if (value == null || value == 'transparent') return Colors.transparent;
    
    // 十六进制颜色
    if (value.startsWith('#')) {
      final hex = value.substring(1);
      if (hex.length == 3) {
        return Color(int.parse('FF${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}', radix: 16));
      }
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
      if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    }
    
    // RGB/RGBA
    if (value.startsWith('rgb')) {
      final match = RegExp(r'rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)').firstMatch(value);
      if (match != null) {
        final r = int.parse(match.group(1)!);
        final g = int.parse(match.group(2)!);
        final b = int.parse(match.group(3)!);
        final a = double.tryParse(match.group(4) ?? '1') ?? 1.0;
        return Color.fromRGBO(r, g, b, a);
      }
    }
    
    // 预定义颜色
    final colorMap = {
      'white': Colors.white,
      'black': Colors.black,
      'red': Colors.red,
      'blue': Colors.blue,
      'green': Colors.green,
      'grey': Colors.grey,
      'gray': Colors.grey,
      'transparent': Colors.transparent,
    };
    
    return colorMap[value.toLowerCase()];
  }

  EdgeInsets _parseEdgeInsets(String? value) {
    if (value == null || value == '0') return EdgeInsets.zero;
    
    final parts = value.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    
    double? top, right, bottom, left;
    
    if (parts.length == 1) {
      final val = _parsePxValue(parts[0]) ?? 0;
      top = right = bottom = left = val;
    } else if (parts.length == 2) {
      top = bottom = _parsePxValue(parts[0]) ?? 0;
      right = left = _parsePxValue(parts[1]) ?? 0;
    } else if (parts.length == 3) {
      top = _parsePxValue(parts[0]) ?? 0;
      right = left = _parsePxValue(parts[1]) ?? 0;
      bottom = _parsePxValue(parts[2]) ?? 0;
    } else if (parts.length == 4) {
      top = _parsePxValue(parts[0]) ?? 0;
      right = _parsePxValue(parts[1]) ?? 0;
      bottom = _parsePxValue(parts[2]) ?? 0;
      left = _parsePxValue(parts[3]) ?? 0;
    }
    
    if (top == null && right == null && bottom == null && left == null) {
      final val = _parsePxValue(value) ?? 0;
      return EdgeInsets.all(val);
    }
    
    return EdgeInsets.fromLTRB(
      left ?? 0,
      top ?? 0,
      right ?? 0,
      bottom ?? 0,
    );
  }

  BorderRadius? _parseBorderRadius(String? value) {
    if (value == null) return null;
    final radius = _parsePxValue(value);
    if (radius != null && radius > 0) {
      return BorderRadius.circular(radius);
    }
    return null;
  }

  List<BoxShadow>? _parseBoxShadow(String? value) {
    if (value == null || value == 'none') return null;
    
    final match = RegExp(r'([\d.]+)px\s+([\d.]+)px\s+([\d.]+)px\s+rgba?\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)').firstMatch(value);
    if (match != null) {
      final offsetX = double.parse(match.group(1)!);
      final offsetY = double.parse(match.group(2)!);
      final blur = double.parse(match.group(3)!);
      final r = int.parse(match.group(4)!);
      final g = int.parse(match.group(5)!);
      final b = int.parse(match.group(6)!);
      final a = double.parse(match.group(7)!);
      
      return [
        BoxShadow(
          offset: Offset(offsetX, offsetY),
          blurRadius: blur,
          color: Color.fromRGBO(r, g, b, a),
        ),
      ];
    }
    return null;
  }

  Map<String, dynamic> _parseBackground(Map<String, String> styles) {
    final map = <String, dynamic>{};
    
    // 处理渐变等
    final bgImage = styles['background-image'];
    if (bgImage != null && bgImage.startsWith('linear-gradient')) {
      // 简单渐变处理
      map['gradient'] = const LinearGradient(colors: [Colors.blue, Colors.purple]);
    }
    
    return map;
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

  // ==================================================================
  // UI主框架（移动端优化）
  // ==================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 地址栏
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      onSubmitted: _fetchWebContent,
                      keyboardType: TextInputType.url,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '输入网址...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _urlController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => _urlController.clear(),
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 40,
                    width: 60,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : () => _fetchWebContent(_urlController.text),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('前往', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
            
            // 加载指示器
            if (_isLoading)
              const LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent),
            
            // 内容区域
            Expanded(
              child: Container(
                color: Colors.white,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: HtmlWidget(
                    _htmlContent,
                    onTapUrl: (url) {
                      _fetchWebContent(url);
                      return true;
                    },
                    customWidgetBuilder: _buildCustomWidget,
                    textStyle: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[800],
                      height: 1.5,
                    ),
                    customStylesBuilder: (element) {
                      final tag = element.localName;
                      if (tag == 'p') {
                        return {'margin-bottom': '12px'};
                      }
                      return {};
                    },
                  ),
                ),
              ),
            ),
            
            // 底部状态栏
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Text(
                _currentUrl.isNotEmpty ? _currentUrl : '就绪',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// 表单组件
// ======================================================================
class _InputWrapper extends StatefulWidget {
  final String type;
  final String placeholder;
  final String value;
  final String name;
  final _FormData? formData;
  final double minHeight;
  final double fontSize;
  final VoidCallback? onSubmit;

  const _InputWrapper({
    required this.type,
    required this.placeholder,
    required this.value,
    required this.name,
    this.formData,
    this.minHeight = 44,
    this.fontSize = 16,
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
    if (widget.formData != null && widget.name.isNotEmpty) {
      if (widget.type == 'checkbox') {
        _isChecked = widget.value.isNotEmpty;
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
        !['checkbox', 'radio', 'submit', 'reset', 'button', 'hidden'].contains(widget.type)) {
      widget.formData!.values[widget.name] = _controller.text;
    }
  }

  void _onFormChanged() {
    if (widget.type == 'radio' && widget.formData != null && mounted) {
      setState(() => _isChecked = widget.formData!.values[widget.name] == widget.value);
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
    final inputDecoration = InputDecoration(
      hintText: widget.placeholder,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.blue),
      ),
    );

    switch (widget.type) {
      case 'text':
      case 'search':
      case 'email':
      case 'password':
      case 'url':
      case 'tel':
      case 'number':
      case 'date':
        return SizedBox(
          height: widget.minHeight,
          child: TextField(
            controller: _controller,
            obscureText: widget.type == 'password',
            style: TextStyle(fontSize: widget.fontSize),
            decoration: inputDecoration,
          ),
        );
      case 'hidden':
        return const SizedBox.shrink();
      case 'submit':
        return SizedBox(
          height: widget.minHeight,
          child: ElevatedButton(
            onPressed: widget.onSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(widget.value.isNotEmpty ? widget.value : '提交'),
          ),
        );
      case 'checkbox':
        return Row(
          children: [
            Checkbox(
              value: _isChecked,
              activeColor: Colors.blue,
              onChanged: (val) {
                setState(() => _isChecked = val ?? false);
                if (widget.formData != null && widget.name.isNotEmpty) {
                  widget.formData!.setValue(widget.name, _isChecked ? widget.value : 'true');
                }
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
          },
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _isChecked ? Colors.blue : Colors.grey,
                    width: 2,
                  ),
                ),
                child: _isChecked
                    ? const Center(
                        child: CircleAvatar(
                          radius: 6,
                          backgroundColor: Colors.blue,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(widget.placeholder.isNotEmpty ? widget.placeholder : widget.value),
              ),
            ],
          ),
        );
      default:
        return SizedBox(
          height: widget.minHeight,
          child: TextField(
            controller: _controller,
            style: TextStyle(fontSize: widget.fontSize),
            decoration: inputDecoration,
          ),
        );
    }
  }
}

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
    final style = ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );

    switch (type) {
      case 'submit':
        return ElevatedButton(
          onPressed: onSubmit,
          style: style.copyWith(
            backgroundColor: WidgetStateProperty.all(Colors.blue),
            foregroundColor: WidgetStateProperty.all(Colors.white),
          ),
          child: Text(text.isEmpty ? '提交' : text),
        );
      case 'reset':
        return ElevatedButton(
          onPressed: () => formData?.values.clear(),
          style: style.copyWith(
            backgroundColor: WidgetStateProperty.all(Colors.grey[400]),
            foregroundColor: WidgetStateProperty.all(Colors.white),
          ),
          child: Text(text.isEmpty ? '重置' : text),
        );
      default:
        return ElevatedButton(
          onPressed: () {},
          style: style.copyWith(
            backgroundColor: WidgetStateProperty.all(Colors.white),
            foregroundColor: WidgetStateProperty.all(Colors.black87),
            side: WidgetStateProperty.all(const BorderSide(color: Colors.grey)),
          ),
          child: Text(text.isEmpty ? '按钮' : text),
        );
    }
  }
}

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
    if (widget.items.isNotEmpty) _selectedValue = widget.items.first.value;
    if (widget.formData != null && widget.name.isNotEmpty) {
      widget.formData!.values[widget.name] = _selectedValue ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: widget.items.any((e) => e.value == _selectedValue) ? _selectedValue : null,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: widget.items
          .map((item) => DropdownMenuItem<String>(
                value: item.value,
                child: Text(item.key),
              ))
          .toList(),
      onChanged: (val) {
        setState(() => _selectedValue = val);
        if (widget.formData != null && widget.name.isNotEmpty) {
          widget.formData!.values[widget.name] = val ?? '';
        }
      },
    );
  }
}

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
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        maxLines: 4,
        decoration: InputDecoration(
          hintText: widget.placeholder,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
}
