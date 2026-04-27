import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../services/local_db/database.dart';

/// Provides the per-user local database instance.
/// Null on web (local DB not supported) and before login.
final localDbProvider = StateProvider<AppDatabase?>((ref) => null);

/// Helper to initialize the database for a logged-in user.
Future<AppDatabase?> initLocalDb(String userId) async {
  if (kIsWeb) return null; // No local DB on web

  try {
    final db = await AppDatabase.open(userId);
    print('✅ Local DB initialized for user: $userId');
    return db;
  } catch (e) {
    print('⚠️ Local DB init failed: $e');
    return null;
  }
}

/// Helper to close the database on logout.
Future<void> closeLocalDb(AppDatabase? db) async {
  try {
    await db?.close();
    print('✅ Local DB closed');
  } catch (e) {
    print('⚠️ Local DB close error: $e');
  }
}
