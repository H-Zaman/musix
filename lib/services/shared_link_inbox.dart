import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_foundation/shared_preferences_foundation.dart';

/// Where a link shared into the app (e.g. from YouTube's share sheet) waits
/// until the app is in the foreground to pick it up.
abstract interface class SharedLinkInbox {
  /// Returns the pending shared text and clears it, or null if none.
  Future<String?> take();
}

/// iOS: the Share Extension can't talk to the app directly, so it stores the
/// link in the shared App Group and opens the app; this reads it from there.
/// (Android delivers shares as intents, handled by receive_sharing_intent.)
class AppGroupLinkInbox implements SharedLinkInbox {
  static const appGroup = 'group.com.shuvro.musix.shared';
  static const key = 'pendingYouTubeURL';

  // Lazy: constructing it needs the platform plugin, which only exists on iOS.
  late final SharedPreferencesAsync _prefs = SharedPreferencesAsync(
    options: SharedPreferencesAsyncFoundationOptions(suiteName: appGroup),
  );

  @override
  Future<String?> take() async {
    if (!Platform.isIOS) return null;
    final pending = await _prefs.getString(key);
    if (pending == null) return null;
    await _prefs.remove(key); // one-shot: never replay an old share
    return pending;
  }
}
