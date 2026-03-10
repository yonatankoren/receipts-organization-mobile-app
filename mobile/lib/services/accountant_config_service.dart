/// Accountant configuration service.
///
/// Manages accountant email and CC addresses for quick receipt export.
/// Backed by SharedPreferences. Also tracks whether the user has seen
/// the first-time export educational popup.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccountantConfigService extends ChangeNotifier {
  static final AccountantConfigService instance = AccountantConfigService._();
  AccountantConfigService._();

  static const String _keyAccountantEmail = 'accountant_email';
  static const String _keyCcEmails = 'accountant_cc_emails';
  static const String _keyHasSeenExportIntro = 'has_seen_export_intro';

  String? _accountantEmail;
  List<String> _ccEmails = [];
  bool _hasSeenExportIntro = false;

  // --- Getters ---

  String? get accountantEmail => _accountantEmail;
  List<String> get ccEmails => _ccEmails;
  bool get hasSeenExportIntro => _hasSeenExportIntro;

  /// True when accountant email is set and non-empty.
  bool get hasAccountantEmail =>
      _accountantEmail != null && _accountantEmail!.trim().isNotEmpty;

  // --- Init ---

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accountantEmail = prefs.getString(_keyAccountantEmail);

    final ccStr = prefs.getString(_keyCcEmails);
    _ccEmails = (ccStr != null && ccStr.isNotEmpty)
        ? ccStr
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : [];

    _hasSeenExportIntro = prefs.getBool(_keyHasSeenExportIntro) ?? false;

    debugPrint(
      'AccountantConfig: init — email=$_accountantEmail, '
      'cc=${_ccEmails.length}, seenIntro=$_hasSeenExportIntro',
    );
    notifyListeners();
  }

  // --- Setters ---

  Future<void> setAccountantEmail(String? email) async {
    final prefs = await SharedPreferences.getInstance();
    _accountantEmail = email?.trim();
    if (_accountantEmail != null && _accountantEmail!.isNotEmpty) {
      await prefs.setString(_keyAccountantEmail, _accountantEmail!);
    } else {
      await prefs.remove(_keyAccountantEmail);
      _accountantEmail = null;
    }
    notifyListeners();
  }

  Future<void> setCcEmails(List<String> emails) async {
    final prefs = await SharedPreferences.getInstance();
    _ccEmails =
        emails.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (_ccEmails.isNotEmpty) {
      await prefs.setString(_keyCcEmails, _ccEmails.join(','));
    } else {
      await prefs.remove(_keyCcEmails);
    }
    notifyListeners();
  }

  Future<void> markExportIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    _hasSeenExportIntro = true;
    await prefs.setBool(_keyHasSeenExportIntro, true);
    notifyListeners();
  }
}
