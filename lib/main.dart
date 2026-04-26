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
      title: 'Mobile Browser',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Mobile Browser'),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ======================================================================
// 纯 Dart 实现的安全 CSS 解析器
// ======================================================================
class _MobileCssParser {
  final List<_CssRule> _rules = [];
  final Map<dom.Element, Map<String, String>> _styleCache = {};
  String _baseUrl = '';
  double _viewportWidth = 375;
  double _viewportHeight = 812;
  double _devicePixelRatio = 2.0;

  static final Map<String, Map<String, String>> _userAgentStyles = {
    '*': {'margin': '0', 'padding': '0', 'box-sizing': 'border-box'},
    'html': {'font-size': '14px', 'scroll-behavior': 'smooth'},
    'body': {'font-family': '-apple-system, sans-serif', 'line-height': '1.5'},
    'div': {'display': 'block'},
    'span': {'display': 'inline'},
    'p': {'display': 'block', 'margin': '0 0 16px 0'},
    'h1': {'display': 'block', 'font-size': '2em', 'font-weight': 'bold'},
    'h2': {'display': 'block', 'font-size': '1.5em', 'font-weight': 'bold'},
    'a': {'text-decoration': 'none', 'color': '#007aff'},
    'img, video': {'max-width': '100%', 'height': 'auto'},
    'button': {'min-height': '44px', 'min-width': '44px', 'padding': '12px 20px', 'font-size': '16px', 'border-radius': '8px'},
    'input': {'min-height': '44px', 'padding': '8px 12px', 'font-size': '16px'},
  };

  final List<_MediaQuery> _mediaQueries = [];

  void clear() {
    _rules.clear();
    _mediaQueries.clear();
    _styleCache.clear();
  }

  void setBaseUrl(String url) => _baseUrl = url;

  void setViewport({required double width, required double height, double pixelRatio = 2.0}) {
    _viewportWidth = width;
    _viewportHeight = height;
    _devicePixelRatio = pixelRatio;
  }

  void parseViewportMeta(String html) {
    final match = RegExp(r'<meta[^>]+name="viewport"[^>]+content="([^"]*)"', caseSensitive: false).firstMatch(html);
    if (match != null) {
      for (final part in (match.group(1) ?? '').split(',')) {
        final t = part.trim();
        if (t.startsWith('width=') && t.substring(6) != 'device-width') {
          _viewportWidth = double.tryParse(t.substring(6)) ?? 375;
        }
      }
    }
  }

  Future<void> parseFromHtml(String html, {http.Client? client, required double screenWidth}) async {
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
    _userAgentStyles.forEach((sel, props) {
      _rules.add(_CssRule(selector: sel, properties: Map.from(props), specificity: sel == '*' ? 0 : 10, source: CssSource.userAgent));
    });
  }

  Future<void> _parseStyleTags(String html) async {
    for (final m in RegExp(r'<style[^>]*>(.*?)</style>', dotAll: true).allMatches(html)) {
      _parseCssText(m.group(1)?.trim() ?? '', CssSource.styleTag);
    }
  }

  Future<void> _fetchExternalStylesheets(String html, http.Client client) async {
    final doc = html_parser.parse(html);
    for (final link in doc.querySelectorAll('link[rel="stylesheet"]')) {
      final href = link.attributes['href'];
      if (href == null || href.isEmpty) continue;
      try {
        final url = _resolveUrl(href);
        final res = await client.get(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) _parseCssText(res.body, CssSource.external);
      } catch (_) {}
    }
  }

  String _resolveUrl(String url) {
    if (url.startsWith('http')) return url;
    final uri = Uri.parse(_baseUrl);
    if (url.startsWith('/')) return '${uri.scheme}://${uri.host}$url';
    final i = uri.path.lastIndexOf('/');
    return '${uri.scheme}://${uri.host}${i > 0 ? uri.path.substring(0, i) : ''}/$url';
  }

  void _parseCssText(String cssText, CssSource source) {
    String cleanCss = cssText.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    final mediaRegex = RegExp(r'@media\s*([^{]+)\{([\s\S]*?)\}\s*\}', caseSensitive: false);
    for (final mediaMatch in mediaRegex.allMatches(cleanCss)) {
      final condition = mediaMatch.group(1)?.trim() ?? '';
      final innerCss = mediaMatch.group(2) ?? '';
      final mediaQuery = _MediaQuery(condition: condition, devicePixelRatio: _devicePixelRatio);
      _parseRulesFromString(innerCss, source, mediaQuery.rules);
      _mediaQueries.add(mediaQuery);
      cleanCss = cleanCss.replaceAll(mediaMatch.group(0)!, '');
    }
    _parseRulesFromString(cleanCss, source, _rules);
  }

  void _parseRulesFromString(String cssStr, CssSource source, List<_CssRule> targetList) {
    final blockRegex = RegExp(r'([^{]+)\{([^}]*)\}');
    for (final match in blockRegex.allMatches(cssStr)) {
      final selector = match.group(1)?.trim() ?? '';
      final propsStr = match.group(2)?.trim() ?? '';
      if (selector.isEmpty || propsStr.isEmpty) continue;

      final props = <String, String>{};
      for (final prop in propsStr.split(';')) {
        final parts = prop.split(':');
        if (parts.length >= 2) {
          final key = parts[0].trim().toLowerCase();
          final value = parts.sublist(1).join(':').trim(); 
          if (key.isNotEmpty) props[key] = value;
        }
      }

      if (props.isNotEmpty) {
        targetList.add(_CssRule(selector: selector, properties: props, specificity: _spec(selector), source: source));
      }
    }
  }

  void _applyMediaQueries(double sw) {
    for (final q in _mediaQueries) {
      if (q.matches(sw, _viewportHeight)) _rules.addAll(q.rules);
    }
  }

  Map<String, String> _parseProps(String str) {
    final m = <String, String>{};
    for (final p in RegExp(r'([\w-]+)\s*:\s*([^;]+);?').allMatches(str)) {
      m[p.group(1)?.trim().toLowerCase() ?? ''] = p.group(2)?.trim() ?? '';
    }
    return m;
  }

  int _spec(String sel) {
    int s = 0;
    s += '#'.allMatches(sel).length * 10000;
    s += '.'.allMatches(sel).length * 100;
    s += '['.allMatches(sel).length * 100;
    if (RegExp(r'^[a-zA-Z]+').hasMatch(sel)) s += 1;
    return s;
  }

  Map<String, String> getComputedStyle(dom.Element element) {
    if (_styleCache.containsKey(element)) return Map.from(_styleCache[element]!);
    final styles = <String, String>{};
    if (_userAgentStyles.containsKey('*')) styles.addAll(_userAgentStyles['*']!);
    final tag = element.localName?.toLowerCase() ?? '';
    if (_userAgentStyles.containsKey(tag)) styles.addAll(_userAgentStyles[tag]!);
    for (final r in _rules) {
      if (_matches(element, r.selector)) styles.addAll(r.properties);
    }
    final inline = element.attributes['style'];
    if (inline != null && inline.isNotEmpty) styles.addAll(_parseProps(inline));
    styles.forEach((k, v) => styles[k] = _resolveValue(v));
    _styleCache[element] = Map.from(styles);
    return styles;
  }

  String _resolveValue(String v) {
    v = v.replaceAllMapped(RegExp(r'calc\(\s*100%\s*-\s*([\d.]+)px\s*\)'), (m) {
      final px = double.parse(m.group(1)!);
      return '${(_viewportWidth - px).round()}px';
    });
    v = v.replaceAllMapped(RegExp(r'([\d.]+)vw'), (m) => '${(double.parse(m.group(1)!) / 100 * _viewportWidth).round()}px');
    v = v.replaceAllMapped(RegExp(r'([\d.]+)vh'), (m) => '${(double.parse(m.group(1)!) / 100 * _viewportHeight).round()}px');
    v = v.replaceAllMapped(RegExp(r'([\d.]+)rem'), (m) => '${(double.parse(m.group(1)!) * 14).round()}px');
    return v;
  }

  bool _matches(dom.Element el, String sel) {
    if (sel == '*' || sel == 'body') return true;
    if (sel == el.localName) return true;
    if (sel.startsWith('.')) return el.classes.contains(sel.substring(1));
    if (sel.startsWith('#')) return el.attributes['id'] == sel.substring(1);
    return sel.split(',').any((s) => s.trim() == el.localName);
  }
}

class _CssRule {
  final String selector;
  final Map<String, String> properties;
  final int specificity;
  final CssSource source;
  _CssRule({required this.selector, required this.properties, required this.specificity, required this.source});
}

class _MediaQuery {
  final String condition;
  final double devicePixelRatio;
  final List<_CssRule> rules = [];
  _MediaQuery({required this.condition, required this.devicePixelRatio});

  bool matches(double sw, double sh) {
    final mw = RegExp(r'max-width:\s*(\d+)px').firstMatch(condition);
    if (mw != null) return sw <= double.parse(mw.group(1)!);
    final miw = RegExp(r'min-width:\s*(\d+)px').firstMatch(condition);
    if (miw != null) return sw >= double.parse(miw.group(1)!);
    if (condition.contains('landscape')) return sw > sh;
    if (condition.contains('portrait')) return sw <= sh;
    return false;
  }
}

enum CssSource { userAgent, external, styleTag, inline }

class _FormData extends ChangeNotifier {
  final String method, action;
  final Map<String, String> values = {};
  _FormData({required this.method, required this.action});
  void setValue(String k, String v) { values[k] = v; notifyListeners(); }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _urlCtrl = TextEditingController();
  String _html = '<meta name="viewport" content="width=device-width, initial-scale=1"><style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:sans-serif;line-height:1.5}.container{display:flex;flex-direction:column;gap:16px;padding:16px}.btn{padding:12px 20px;min-height:44px;font-size:16px;border-radius:8px;background:#007aff;color:white;border:none;display:inline-block}.grid-2{display:grid;grid-template-columns:1fr 1fr;gap:12px}.card{background:white;border-radius:8px;padding:16px;box-shadow:0 2px 8px rgba(0,0,0,0.1)}</style><div class="container"><h1>Demo</h1><div class="grid-2"><div class="card">Grid 1</div><div class="card">Grid 2</div></div><button class="btn">Click Me</button></div>';
  bool _loading = false;
  String _url = '';
  final Map<int, _FormData> _forms = {};
  late _MobileCssParser _cssParser;
  http.Client? _client;

  @override
  void initState() {
    super.initState();
    _cssParser = _MobileCssParser();
    _client = http.Client();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final s = MediaQuery.of(context).size;
    _cssParser.setViewport(width: s.width, height: s.height, pixelRatio: MediaQuery.of(context).devicePixelRatio);
    await _cssParser.parseFromHtml(_html, client: _client, screenWidth: s.width);
    if (mounted) setState(() {});
  }

  @override
  void dispose() { _client?.close(); _urlCtrl.dispose(); super.dispose(); }

  Future<void> _update(String html, String baseUrl) async {
    _cssParser.setBaseUrl(baseUrl);
    final s = MediaQuery.of(context).size;
    _cssParser.setViewport(width: s.width, height: s.height, pixelRatio: MediaQuery.of(context).devicePixelRatio);
    await _cssParser.parseFromHtml(html, client: _client, screenWidth: s.width);
    if (mounted) setState(() {});
  }

  // 修复点：将 n 赋值给 formElement，避免闭包内的 null 安全错误
  _FormData? _formOf(dom.Element el) {
    dom.Node? n = el.parent;
    while (n != null) {
      if (n is dom.Element && n.localName == 'form') {
        final formElement = n; // 提前赋值，保留非空类型提升
        return _forms.putIfAbsent(formElement.hashCode, () => _FormData(
          method: formElement.attributes['method']?.toLowerCase() ?? 'get', 
          action: formElement.attributes['action'] ?? ''
        ));
      }
      n = n.parent;
    }
    return null;
  }

  String _resolve(String url) {
    if (url.startsWith('http')) return url;
    if (_url.isEmpty) return 'https://$url';
    final u = Uri.parse(_url);
    if (url.startsWith('/')) return '${u.scheme}://${u.host}$url';
    final i = u.path.lastIndexOf('/');
    return '${u.scheme}://${u.host}${i > 0 ? u.path.substring(0, i) : ''}/$url';
  }

  Future<void> _go(String url) async {
    if (url.isEmpty) return;
    final full = _resolve(url);
    setState(() { _loading = true; _url = full; _urlCtrl.text = full; _forms.clear(); });
    try {
      final r = await http.get(Uri.parse(full), headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) { setState(() => _html = r.body); await _update(r.body, full); }
      else { setState(() => _html = '<p style="color:red">Error: ${r.statusCode}</p>'); }
    } catch (e) { setState(() => _html = '<p style="color:red">$e</p>'); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _submit(_FormData fd) async {
    final full = fd.action.isNotEmpty ? _resolve(fd.action) : _url;
    if (full.isEmpty) return;
    setState(() => _loading = true);
    try {
      final data = Map.fromEntries(fd.values.entries.where((e) => e.key.isNotEmpty));
      http.Response r;
      if (fd.method == 'post') {
        r = await http.post(Uri.parse(full), headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: data).timeout(const Duration(seconds: 10));
      } else {
        final qs = data.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');
        r = await http.get(Uri.parse(qs.isNotEmpty ? '$full?$qs' : full)).timeout(const Duration(seconds: 10));
      }
      setState(() { _url = full; _urlCtrl.text = full; _html = r.body; });
      await _update(r.body, full);
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Widget? _buildCustom(dom.Element el) {
    final tag = el.localName;
    if (tag == 'input') return _input(el);
    if (tag == 'button') return _button(el);
    if (tag == 'select') return _select(el);
    if (tag == 'textarea') return _textarea(el);
    if (tag == 'option' || tag == 'style' || tag == 'meta' || tag == 'link' || tag == 'script' || tag == 'head') return const SizedBox.shrink();

    final st = _cssParser.getComputedStyle(el);
    final d = st['display'];
    if (d == 'flex' || d == 'inline-flex') return _flex(el, st);
    if (d == 'grid' || d == 'inline-grid') return _grid(el, st);
    if (tag == 'img') return _img(el, st);
    if (tag == 'a') return _link(el, st);
    return _styled(el, st);
  }

  Widget _flex(dom.Element el, Map<String, String> st) {
    final dir = st['flex-direction'] == 'column' ? Axis.vertical : Axis.horizontal;
    final wrap = st['flex-wrap'] == 'wrap';
    final gap = _px(st['gap']);
    Widget child;
    if (wrap) {
      child = Wrap(spacing: gap ?? 8, runSpacing: gap ?? 8, children: el.children.map((c) => HtmlWidget(c.outerHtml, customWidgetBuilder: _buildCustom)).toList());
    } else {
      child = Flex(direction: dir, mainAxisAlignment: _main(st['justify-content']), crossAxisAlignment: _cross(st['align-items']), children: _gap(el.children.map((c) => HtmlWidget(c.outerHtml, customWidgetBuilder: _buildCustom)).toList(), gap, dir));
    }
    child = Container(margin: _insets(st['margin']), padding: _insets(st['padding']), constraints: BoxConstraints(maxWidth: _px(st['max-width']) ?? double.infinity), decoration: BoxDecoration(color: _color(st['background-color']), borderRadius: _radius(st['border-radius']), boxShadow: _shadow(st['box-shadow']), border: _border(st['border-bottom'])), child: child);
    return _wrapWithEffects(child, st);
  }

  Widget _grid(dom.Element el, Map<String, String> st) {
    final cols = st['grid-template-columns']?.split(' ').where((s) => s.trim().isNotEmpty).length ?? 1;
    final gap = _px(st['gap']);
    final p = _insets(st['padding']);
    Widget child = IntrinsicHeight(child: Container(margin: _insets(st['margin']), padding: p, constraints: BoxConstraints(maxWidth: _px(st['max-width']) ?? double.infinity), decoration: BoxDecoration(color: _color(st['background-color']), borderRadius: _radius(st['border-radius'])), child: LayoutBuilder(builder: (_, c) {
      final usableWidth = (c.maxWidth.isFinite ? c.maxWidth : MediaQuery.of(context).size.width) - p.horizontal - (cols - 1) * (gap ?? 8);
      final w = (usableWidth / cols).clamp(0.0, double.infinity);
      return Wrap(spacing: gap ?? 8, runSpacing: gap ?? 8, children: el.children.map((ch) => SizedBox(width: w, child: HtmlWidget(ch.outerHtml, customWidgetBuilder: _buildCustom))).toList());
    })));
    return _wrapWithEffects(child, st);
  }

  Widget _img(dom.Element el, Map<String, String> st) {
    final src = el.attributes['src'] ?? '';
    Widget child = Container(margin: _insets(st['margin']), child: src.isNotEmpty ? ClipRRect(borderRadius: _radius(st['border-radius']) ?? BorderRadius.zero, child: Image.network(src, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _placeholder())) : _placeholder());
    return _wrapWithEffects(child, st);
  }

  Widget _placeholder() => Container(height: 200, color: Colors.grey[300], child: const Center(child: Icon(Icons.broken_image)));

  Widget _link(dom.Element el, Map<String, String> st) {
    final href = el.attributes['href'] ?? '';
    Widget child = GestureDetector(onTap: () { if (href.isNotEmpty) _go(_resolve(href)); }, child: Container(margin: _insets(st['margin']), padding: _insets(st['padding']), constraints: BoxConstraints(minHeight: _px(st['min-height']) ?? 44), child: HtmlWidget(el.innerHtml, customWidgetBuilder: _buildCustom, textStyle: TextStyle(color: _color(st['color']) ?? const Color(0xFF007AFF)))));
    return _wrapWithEffects(child, st);
  }

  Widget? _styled(dom.Element el, Map<String, String> st) {
    final bg = _color(st['background-color']);
    final p = _insets(st['padding']);
    final m = _insets(st['margin']);
    final r = _radius(st['border-radius']);
    final border = _border(st['border-bottom']);
    final shadow = _shadow(st['box-shadow']);
    final maxWidth = _px(st['max-width']);
    final noWrap = st['white-space'] == 'nowrap';
    if (bg == null && p == EdgeInsets.zero && m == EdgeInsets.zero && r == null && border == null && shadow == null && maxWidth == null && noWrap == false) return null;
    Widget child = HtmlWidget(el.innerHtml, customWidgetBuilder: _buildCustom, textStyle: TextStyle(fontSize: 14, overflow: noWrap ? TextOverflow.ellipsis : null));
    if (m != EdgeInsets.zero || p != EdgeInsets.zero || bg != null || r != null || border != null || shadow != null || maxWidth != null) {
      child = Container(margin: m, padding: p, constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity), decoration: BoxDecoration(color: bg, borderRadius: r, border: border, boxShadow: shadow), child: child);
    }
    return _wrapWithEffects(child, st);
  }

  Widget _input(dom.Element el) {
    final fd = _formOf(el);
    return _InputW(type: el.attributes['type'] ?? 'text', placeholder: el.attributes['placeholder'] ?? '', value: el.attributes['value'] ?? '', name: el.attributes['name'] ?? '', formData: fd, onSubmit: fd != null ? () => _submit(fd) : null);
  }

  Widget _button(dom.Element el) {
    final fd = _formOf(el);
    final st = _cssParser.getComputedStyle(el);
    return _wrapWithEffects(_BtnW(type: el.attributes['type'] ?? 'button', text: el.innerHtml, formData: fd, onSubmit: fd != null ? () => _submit(fd) : null), st);
  }

  Widget _select(dom.Element el) {
    final fd = _formOf(el);
    final items = el.getElementsByTagName('option').map((o) => MapEntry(o.text.trim(), o.attributes['value'] ?? o.text.trim())).toList();
    return _SelW(items: items, name: el.attributes['name'] ?? '', formData: fd);
  }

  Widget _textarea(dom.Element el) {
    final fd = _formOf(el);
    return _TxtW(name: el.attributes['name'] ?? '', placeholder: el.attributes['placeholder'] ?? '', value: el.text.trim(), formData: fd);
  }

  Widget _wrapWithEffects(Widget child, Map<String, String> st) {
    final opacityVal = st['opacity'];
    if (opacityVal != null) { final opacity = double.tryParse(opacityVal); if (opacity != null && opacity < 1.0) child = Opacity(opacity: opacity, child: child); }
    final transformStr = st['transform'] ?? '';
    final scaleMatch = RegExp(r'scale\(([\d.]+)\)').firstMatch(transformStr);
    if (scaleMatch != null) { final scale = double.parse(scaleMatch.group(1)!); child = Transform.scale(scale: scale, child: child); }
    if (st['overflow-x'] == 'auto') { child = SingleChildScrollView(scrollDirection: Axis.horizontal, child: child); }
    return child;
  }

  List<Widget> _gap(List<Widget> c, double? g, Axis d) {
    if (g == null || c.isEmpty) return c;
    return List.generate(c.length * 2 - 1, (i) => i.isOdd ? SizedBox(width: d == Axis.horizontal ? g : 0, height: d == Axis.vertical ? g : 0) : c[i ~/ 2]);
  }

  double? _px(String? v) { if (v == null) return null; final m = RegExp(r'([\d.]+)').firstMatch(v); return m != null ? double.tryParse(m.group(1)!) : null; }

  Color? _color(String? v) {
    if (v == null || v == 'transparent') return null;
    if (v == 'white') return const Color(0xFFFFFFFF);
    if (v == 'black') return const Color(0xFF000000);
    if (v.startsWith('#')) {
      final h = v.substring(1);
      if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
      if (h.length == 3) return Color(int.parse('FF${h[0]}${h[0]}${h[1]}${h[1]}${h[2]}${h[2]}', radix: 16));
    }
    final rgbMatch = RegExp(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+))?\s*\)').firstMatch(v);
    if (rgbMatch != null) return Color.fromRGBO(int.parse(rgbMatch.group(1)!), int.parse(rgbMatch.group(2)!), int.parse(rgbMatch.group(3)!), rgbMatch.group(4) != null ? double.parse(rgbMatch.group(4)!) : 1.0);
    return null;
  }

  EdgeInsets _insets(String? v) {
    if (v == null || v == '0') return EdgeInsets.zero;
    final parts = v.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.length == 1) return EdgeInsets.all(_px(parts[0]) ?? 0);
    if (parts.length == 2) return EdgeInsets.symmetric(vertical: _px(parts[0]) ?? 0, horizontal: _px(parts[1]) ?? 0);
    if (parts.length == 4) return EdgeInsets.fromLTRB(_px(parts[3]) ?? 0, _px(parts[0]) ?? 0, _px(parts[1]) ?? 0, _px(parts[2]) ?? 0);
    return EdgeInsets.all(_px(v) ?? 0);
  }

  BorderRadius? _radius(String? v) { final r = _px(v); return r != null && r > 0 ? BorderRadius.circular(r) : null; }

  Border? _border(String? v) {
    if (v == null || v == 'none') return null;
    final m = RegExp(r'([\d.]+)px\s+solid\s+(#[0-9a-fA-F]{3,6})').firstMatch(v);
    if (m != null) return Border(bottom: BorderSide(color: _color(m.group(2))!, width: double.parse(m.group(1)!)));
    return null;
  }

  List<BoxShadow>? _shadow(String? v) {
    if (v == null || v == 'none') return null;
    final m = RegExp(r'([\d.]+)px\s+([\d.]+)px\s+([\d.]+)px\s+rgba?\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)').firstMatch(v);
    if (m != null) return [BoxShadow(offset: Offset(double.parse(m.group(1)!), double.parse(m.group(2)!)), blurRadius: double.parse(m.group(3)!), color: Color.fromRGBO(int.parse(m.group(4)!), int.parse(m.group(5)!), int.parse(m.group(6)!), double.parse(m.group(7)!)))];
    return null;
  }

  MainAxisAlignment _main(String? v) {
    switch (v) { case 'center': return MainAxisAlignment.center; case 'flex-end': return MainAxisAlignment.end; case 'space-between': return MainAxisAlignment.spaceBetween; case 'space-around': return MainAxisAlignment.spaceAround; case 'space-evenly': return MainAxisAlignment.spaceEvenly; default: return MainAxisAlignment.start; }
  }

  CrossAxisAlignment _cross(String? v) {
    switch (v) { case 'center': return CrossAxisAlignment.center; case 'flex-end': return CrossAxisAlignment.end; case 'stretch': return CrossAxisAlignment.stretch; default: return CrossAxisAlignment.center; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), backgroundColor: Theme.of(context).colorScheme.inversePrimary),
      body: Column(
        children: [
          Container(padding: const EdgeInsets.all(8), child: Row(children: [
            Expanded(child: TextField(controller: _urlCtrl, onSubmitted: _go, decoration: InputDecoration(hintText: 'URL...', contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)), filled: true, fillColor: Colors.grey[100]))),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _loading ? null : () => _go(_urlCtrl.text), child: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Go'))
          ])),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(12), child: HtmlWidget(_html, onTapUrl: (url) { _go(url); return true; }, customWidgetBuilder: _buildCustom, textStyle: const TextStyle(fontSize: 14, height: 1.5)))),
          Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), color: Colors.grey[100], child: Text(_url.isNotEmpty ? _url : 'Ready', style: const TextStyle(fontSize: 11, color: Colors.grey), overflow: TextOverflow.ellipsis))
        ],
      ),
    );
  }
}

class _InputW extends StatefulWidget {
  final String type, placeholder, value, name;
  final _FormData? formData;
  final VoidCallback? onSubmit;
  const _InputW({required this.type, required this.placeholder, required this.value, required this.name, this.formData, this.onSubmit});
  @override
  State<_InputW> createState() => _InputWState();
}

class _InputWState extends State<_InputW> {
  late TextEditingController _ctrl;
  bool _checked = false;
  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
    if (widget.formData != null && widget.name.isNotEmpty) {
      if (widget.type == 'checkbox') { _checked = widget.value.isNotEmpty; widget.formData!.values[widget.name] = _checked ? widget.value : ''; }
      else if (widget.type == 'radio') { _checked = widget.formData!.values[widget.name] == widget.value; }
      else { widget.formData!.values[widget.name] = widget.value; }
    }
    _ctrl.addListener(() { if (widget.formData != null && widget.name.isNotEmpty && !['checkbox', 'radio', 'submit', 'reset', 'button', 'hidden'].contains(widget.type)) widget.formData!.values[widget.name] = _ctrl.text; });
    widget.formData?.addListener(() { if (widget.type == 'radio' && mounted) setState(() => _checked = widget.formData!.values[widget.name] == widget.value); });
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final deco = InputDecoration(hintText: widget.placeholder, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)));
    switch (widget.type) {
      case 'text': case 'search': case 'email': case 'password': case 'url': case 'tel': case 'number': return SizedBox(height: 44, child: TextField(controller: _ctrl, obscureText: widget.type == 'password', decoration: deco));
      case 'submit': return SizedBox(height: 44, child: ElevatedButton(onPressed: widget.onSubmit, style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: Text(widget.value.isNotEmpty ? widget.value : 'Submit')));
      case 'checkbox': return Row(children: [Checkbox(value: _checked, onChanged: (v) { setState(() => _checked = v ?? false); widget.formData?.setValue(widget.name, _checked ? widget.value : ''); }), Text(widget.placeholder.isNotEmpty ? widget.placeholder : widget.name)]);
      case 'radio': return GestureDetector(onTap: () => widget.formData?.setValue(widget.name, widget.value), child: Row(children: [Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _checked ? Colors.blue : Colors.grey, width: 2)), child: _checked ? const Center(child: CircleAvatar(radius: 6, backgroundColor: Colors.blue)) : null), const SizedBox(width: 8), Text(widget.placeholder.isNotEmpty ? widget.placeholder : widget.value)]));
      default: return SizedBox(height: 44, child: TextField(controller: _ctrl, decoration: deco));
    }
  }
}

class _BtnW extends StatelessWidget {
  final String type, text;
  final _FormData? formData;
  final VoidCallback? onSubmit;
  const _BtnW({required this.type, required this.text, this.formData, this.onSubmit});
  @override
  Widget build(BuildContext context) {
    final style = ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)));
    switch (type) {
      case 'submit': return ElevatedButton(onPressed: onSubmit, style: style.copyWith(backgroundColor: WidgetStateProperty.all(Colors.blue), foregroundColor: WidgetStateProperty.all(Colors.white)), child: Text(text.isEmpty ? 'Submit' : text));
      case 'reset': return ElevatedButton(onPressed: () => formData?.values.clear(), style: style.copyWith(backgroundColor: WidgetStateProperty.all(Colors.grey), foregroundColor: WidgetStateProperty.all(Colors.white)), child: Text(text.isEmpty ? 'Reset' : text));
      default: return ElevatedButton(onPressed: () {}, style: style, child: Text(text.isEmpty ? 'Button' : text));
    }
  }
}

class _SelW extends StatefulWidget {
  final List<MapEntry<String, String>> items;
  final String name;
  final _FormData? formData;
  const _SelW({required this.items, required this.name, this.formData});
  @override
  State<_SelW> createState() => _SelWState();
}

class _SelWState extends State<_SelW> {
  String? _val;
  @override
  void initState() { super.initState(); if (widget.items.isNotEmpty) _val = widget.items.first.value; if (widget.formData != null && widget.name.isNotEmpty) widget.formData!.values[widget.name] = _val ?? ''; }
  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(value: _val, items: widget.items.map((item) => DropdownMenuItem<String>(value: item.value, child: Text(item.key))).toList(), onChanged: (String? newValue) { setState(() { _val = newValue; if (widget.formData != null && widget.name.isNotEmpty) widget.formData!.values[widget.name] = newValue ?? ''; }); });
  }
}

class _TxtW extends StatefulWidget {
  final String name, placeholder, value;
  final _FormData? formData;
  const _TxtW({required this.name, required this.placeholder, required this.value, this.formData});
  @override
  State<_TxtW> createState() => _TxtWState();
}

class _TxtWState extends State<_TxtW> {
  late TextEditingController _ctrl;
  @override
  void initState() { super.initState(); _ctrl = TextEditingController(text: widget.value); if (widget.formData != null && widget.name.isNotEmpty) widget.formData!.values[widget.name] = widget.value; _ctrl.addListener(() { if (widget.formData != null && widget.name.isNotEmpty) widget.formData!.values[widget.name] = _ctrl.text; }); }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return TextField(controller: _ctrl, maxLines: 3, decoration: InputDecoration(hintText: widget.placeholder, alignLabelWithHint: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.all(12)));
  }
}
