/// Google Sign-In authentication service.
/// Handles OAuth for Drive and Sheets scopes.
/// No secrets stored in the app — only OAuth tokens managed by Google Sign-In SDK.

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as gauth;
import 'package:http/http.dart' as http;
import '../utils/constants.dart';

class AuthService extends ChangeNotifier {
  static final AuthService instance = AuthService._();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: AppConstants.googleScopes,
  );

  GoogleSignInAccount? _currentUser;
  GoogleSignInAccount? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;

  AuthService._() {
    _googleSignIn.onCurrentUserChanged.listen((account) {
      _currentUser = account;
      notifyListeners();
    });
  }

  /// Initialize: check for existing sign-in silently
  Future<void> init() async {
    try {
      _currentUser = await _googleSignIn.signInSilently();
      notifyListeners();
    } catch (e) {
      debugPrint('Silent sign-in failed: $e');
    }
  }

  /// Interactive sign-in
  Future<bool> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      notifyListeners();
      return _currentUser != null;
    } catch (e) {
      debugPrint('Sign-in error: $e');
      return false;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    notifyListeners();
  }

  /// Get an authenticated HTTP client for Google API calls (Drive, Sheets).
  /// Returns null if not signed in.
  Future<http.Client?> getAuthenticatedClient() async {
    final account = _currentUser ?? await _googleSignIn.signInSilently();
    if (account == null) return null;

    final auth = await account.authentication;
    final accessToken = auth.accessToken;
    if (accessToken == null) return null;

    // Create an authenticated client using the access token
    final credentials = gauth.AccessCredentials(
      gauth.AccessToken(
        'Bearer',
        accessToken,
        // Token expiry — Google Sign-In manages refresh internally.
        // Set a reasonable expiry; the client will work as long as the
        // underlying token is valid.
        DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
      auth.idToken,
      AppConstants.googleScopes,
    );

    return gauth.authenticatedClient(http.Client(), credentials);
  }

  /// Get raw access token for manual API calls
  Future<String?> getAccessToken() async {
    final account = _currentUser ?? await _googleSignIn.signInSilently();
    if (account == null) return null;
    final auth = await account.authentication;
    return auth.accessToken;
  }
}

