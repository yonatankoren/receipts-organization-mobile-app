/// Share service — handles Android Share and Gmail direct send.
///
/// Two modes:
///   - Generic Share: opens the Android share chooser with a ZIP file.
///   - Gmail Direct: opens Gmail pre-addressed to the accountant with ZIP attached.
///     Falls back to generic share if Gmail is not installed.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

class ShareService {
  static const _channel = MethodChannel('com.receipts.app/share');

  /// Share a file via the standard Android share chooser.
  static Future<void> shareFile({
    required String filePath,
    String? subject,
  }) async {
    await Share.shareXFiles(
      [XFile(filePath)],
      subject: subject,
    );
  }

  /// Open Gmail with pre-filled recipient, CC, subject, and ZIP attachment.
  ///
  /// Falls back to generic share if Gmail is not available on the device.
  static Future<void> sendViaGmail({
    required String filePath,
    required String recipientEmail,
    List<String> ccEmails = const [],
    String? subject,
  }) async {
    try {
      await _channel.invokeMethod('sendGmail', {
        'filePath': filePath,
        'recipient': recipientEmail,
        'cc': ccEmails,
        'subject': subject ?? 'קבלות',
      });
    } on PlatformException catch (e) {
      if (e.code == 'GMAIL_UNAVAILABLE') {
        debugPrint('ShareService: Gmail not available, falling back to share');
        await shareFile(filePath: filePath, subject: subject);
      } else {
        rethrow;
      }
    }
  }
}
