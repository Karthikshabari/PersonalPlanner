// The platform interface is a transitive dependency of url_launcher; tests
// replace it so no real browser is ever started.
// ignore_for_file: depend_on_referenced_packages

import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records every launch and answers with a scripted result.
class FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launched = <String>[];
  final List<LaunchOptions> options = <LaunchOptions>[];
  int canLaunchCalls = 0;

  /// What [launchUrl] returns.
  bool result = true;

  /// When set, [launchUrl] throws this instead.
  Object? error;

  /// Replaces the real platform with this fake; call from `setUp`.
  void install() => UrlLauncherPlatform.instance = this;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async {
    canLaunchCalls++;
    return false;
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    this.options.add(options);
    final failure = error;
    if (failure != null) throw failure;
    return result;
  }
}
