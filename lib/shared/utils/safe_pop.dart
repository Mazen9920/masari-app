import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Extension on [BuildContext] that provides a safe version of [GoRouterHelper.pop].
///
/// Prevents `GoError: There is nothing to pop` by checking [canPop] first.
/// If the navigation stack is empty (e.g. at a shell-route root tab),
/// falls back to navigating to `/home`.
extension SafePopX on BuildContext {
  /// Pops the current route if possible; otherwise navigates to `/home`.
  void safePop<T extends Object?>([T? result]) {
    if (canPop()) {
      pop<T>(result);
    } else {
      go('/home');
    }
  }
}
