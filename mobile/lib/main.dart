/// Entry point for the Receipts app.
///
/// Initialization order:
///   1. Flutter bindings
///   2. Google Sign-In (silent, non-blocking)
///   3. Storage config (load cached IDs)
///   4. Sync engine (connectivity monitor + job processor)
///   5. Launch app → HomeRouter decides first screen

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/auth_service.dart';
import 'services/storage_config_service.dart';
import 'services/sync_engine.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait for consistent receipt capture
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Initialize services (non-blocking)
  await AuthService.instance.init();
  await StorageConfigService.instance.init();
  SyncEngine.instance.init();

  runApp(const ReceiptsApp());
}
