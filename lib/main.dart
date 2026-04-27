static JavascriptRuntime _createRuntime() {
  final js = getJavascriptRuntime();
  
  // 注入必要的全局变量（如window、document）
  js.evaluate(r'''
    var window = {};
    var document = {};
    // 其他依赖的全局对象...
  ''');

  // 其他初始化代码...
  return js;
}
