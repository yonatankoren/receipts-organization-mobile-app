/// SQLite database helper.
/// Manages local persistence for receipts and sync jobs.
/// This is the single source of truth while offline.

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/receipt.dart';
import '../models/sync_job.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._();
  static Database? _database;

  DatabaseHelper._();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'receipts.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Receipts table
    await db.execute('''
      CREATE TABLE receipts (
        id TEXT PRIMARY KEY,
        capture_timestamp INTEGER NOT NULL,
        image_path TEXT NOT NULL,
        merchant_name TEXT,
        receipt_date TEXT,
        total_amount REAL,
        currency TEXT DEFAULT 'ILS',
        category TEXT,
        drive_file_id TEXT,
        drive_file_link TEXT,
        raw_ocr_text TEXT,
        overall_confidence REAL,
        field_confidences TEXT,
        status TEXT DEFAULT 'captured',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Sync jobs table
    await db.execute('''
      CREATE TABLE sync_jobs (
        id TEXT PRIMARY KEY,
        receipt_id TEXT NOT NULL,
        job_type TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        retry_count INTEGER DEFAULT 0,
        max_retries INTEGER DEFAULT 5,
        next_retry_at INTEGER,
        error_message TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (receipt_id) REFERENCES receipts(id)
      )
    ''');

    // Indexes for efficient queries
    await db.execute(
        'CREATE INDEX idx_receipts_status ON receipts(status)');
    await db.execute(
        'CREATE INDEX idx_receipts_capture ON receipts(capture_timestamp DESC)');
    await db.execute(
        'CREATE INDEX idx_jobs_status ON sync_jobs(status)');
    await db.execute(
        'CREATE INDEX idx_jobs_receipt ON sync_jobs(receipt_id)');
    await db.execute(
        'CREATE INDEX idx_jobs_type_status ON sync_jobs(job_type, status)');
  }

  // ===== RECEIPT OPERATIONS =====

  Future<void> insertReceipt(Receipt receipt) async {
    final db = await database;
    await db.insert(
      'receipts',
      receipt.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateReceipt(Receipt receipt) async {
    final db = await database;
    receipt.updatedAt = DateTime.now();
    await db.update(
      'receipts',
      receipt.toMap(),
      where: 'id = ?',
      whereArgs: [receipt.id],
    );
  }

  Future<Receipt?> getReceipt(String id) async {
    final db = await database;
    final maps = await db.query('receipts', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Receipt.fromMap(maps.first);
  }

  Future<List<Receipt>> getAllReceipts() async {
    final db = await database;
    final maps = await db.query(
      'receipts',
      orderBy: 'capture_timestamp DESC',
    );
    return maps.map((m) => Receipt.fromMap(m)).toList();
  }

  Future<List<Receipt>> getReceiptsByMonth(String monthKey) async {
    final db = await database;
    // monthKey is "YYYY-MM", match against receipt_date or capture_timestamp
    final maps = await db.query(
      'receipts',
      where: "receipt_date LIKE ? OR receipt_date IS NULL",
      whereArgs: ['$monthKey%'],
      orderBy: 'capture_timestamp DESC',
    );
    // For receipts without receipt_date, filter by capture_timestamp month
    final all = maps.map((m) => Receipt.fromMap(m)).toList();
    return all.where((r) => r.monthKey == monthKey).toList();
  }

  Future<int> getPendingSyncCount() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(DISTINCT receipt_id) as cnt FROM sync_jobs WHERE status IN ('pending', 'failed')",
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<Map<String, int>> getMonthCounts() async {
    final receipts = await getAllReceipts();
    final counts = <String, int>{};
    for (final r in receipts) {
      counts[r.monthKey] = (counts[r.monthKey] ?? 0) + 1;
    }
    return counts;
  }

  // ===== SYNC JOB OPERATIONS =====

  Future<void> insertJob(SyncJob job) async {
    final db = await database;
    await db.insert(
      'sync_jobs',
      job.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateJob(SyncJob job) async {
    final db = await database;
    job.updatedAt = DateTime.now();
    await db.update(
      'sync_jobs',
      job.toMap(),
      where: 'id = ?',
      whereArgs: [job.id],
    );
  }

  /// Get next ready job, respecting execution order:
  /// For each receipt: uploadImage → processReceipt → sheetsAppend
  Future<SyncJob?> getNextReadyJob() async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Get all pending/failed jobs that are ready to execute
    final maps = await db.query(
      'sync_jobs',
      where: "(status = 'pending' OR status = 'failed') "
          "AND retry_count < max_retries "
          "AND (next_retry_at IS NULL OR next_retry_at <= ?)",
      whereArgs: [now],
      orderBy: 'created_at ASC',
    );

    if (maps.isEmpty) return null;

    final jobs = maps.map((m) => SyncJob.fromMap(m)).toList();

    // Find the first job whose dependencies are met
    for (final job in jobs) {
      if (await _areDependenciesMet(job)) {
        return job;
      }
    }

    return null;
  }

  /// Check if a job's predecessor jobs for the same receipt are complete
  Future<bool> _areDependenciesMet(SyncJob job) async {
    final db = await database;

    // Define job order
    final predecessors = <JobType>[];
    switch (job.jobType) {
      case JobType.processReceipt:
        // processReceipt can run independently (uses local image)
        break;
      case JobType.sheetsAppend:
        // sheetsAppend needs both uploadImage and processReceipt to be done
        predecessors.addAll([JobType.uploadImage, JobType.processReceipt]);
        break;
      case JobType.uploadImage:
        // uploadImage has no dependencies
        break;
    }

    for (final predType in predecessors) {
      final predJobs = await db.query(
        'sync_jobs',
        where: "receipt_id = ? AND job_type = ?",
        whereArgs: [job.receiptId, predType.name],
      );
      // If predecessor exists and is not completed, dependency not met
      for (final pMap in predJobs) {
        final pJob = SyncJob.fromMap(pMap);
        if (pJob.status != JobStatus.completed) {
          return false;
        }
      }
    }

    return true;
  }

  Future<List<SyncJob>> getJobsForReceipt(String receiptId) async {
    final db = await database;
    final maps = await db.query(
      'sync_jobs',
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
      orderBy: 'created_at ASC',
    );
    return maps.map((m) => SyncJob.fromMap(m)).toList();
  }

  Future<int> getPendingJobCount() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM sync_jobs WHERE status IN ('pending', 'failed') AND retry_count < max_retries",
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// Check if a specific job type is already completed for a receipt (idempotency)
  Future<bool> isJobCompleted(String receiptId, JobType jobType) async {
    final db = await database;
    final maps = await db.query(
      'sync_jobs',
      where: "receipt_id = ? AND job_type = ? AND status = 'completed'",
      whereArgs: [receiptId, jobType.name],
    );
    return maps.isNotEmpty;
  }

  /// Delete old local images for fully synced receipts (cleanup)
  Future<List<String>> getCleanableImagePaths({int olderThanDays = 30}) async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: olderThanDays))
        .millisecondsSinceEpoch;
    final maps = await db.query(
      'receipts',
      columns: ['image_path'],
      where: "status = 'synced' AND drive_file_id IS NOT NULL AND capture_timestamp < ?",
      whereArgs: [cutoff],
    );
    return maps.map((m) => m['image_path'] as String).toList();
  }
}

