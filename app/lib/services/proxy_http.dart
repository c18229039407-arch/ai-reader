import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 常见本机代理端口（Clash/ClashX 7890、V2Ray 1087、Privoxy 8118 等）。
/// 背景：Dart HttpClient 不读 macOS 系统代理设置，浏览器能访问的境外站点
/// App 直连可能不通——自动探测这些端口可无感修复公版书搜索（A2 国内可用性）。
const commonLocalProxies = [
  '127.0.0.1:7890',
  '127.0.0.1:7897',
  '127.0.0.1:1087',
  '127.0.0.1:8118',
  '127.0.0.1:8888',
];

/// 构建走指定代理的 http 客户端。
http.Client clientViaProxy(String hostPort) {
  final hc = HttpClient()
    ..findProxy = ((_) => 'PROXY $hostPort')
    ..connectionTimeout = const Duration(seconds: 6);
  return IOClient(hc);
}
