/// Sync job model — represents a queued background task.
/// Jobs are processed in order per receipt: upload → process → sheets_append.
/// Each job is idempotent: safe to retry without duplicating effects.

class SyncJob {
  final String id; // UUID
  final String receiptId; // FK to Receipt
  final JobType jobType;
  JobStatus status;
  int retryCount;
  final int maxRetries;
  DateTime? nextRetryAt;
  String? errorMessage;
  DateTime createdAt;
  DateTime updatedAt;

  SyncJob({
    required this.id,
    required this.receiptId,
    required this.jobType,
    this.status = JobStatus.pending,
    this.retryCount = 0,
    this.maxRetries = 5,
    this.nextRetryAt,
    this.errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Whether this job can be executed now
  bool get isReady {
    if (status != JobStatus.pending && status != JobStatus.failed) return false;
    if (retryCount >= maxRetries) return false;
    if (nextRetryAt != null && DateTime.now().isBefore(nextRetryAt!)) return false;
    return true;
  }

  /// Whether this job has permanently failed
  bool get isPermanentlyFailed =>
      status == JobStatus.failed && retryCount >= maxRetries;

  /// Compute next retry delay with exponential backoff
  Duration get nextRetryDelay {
    const baseDelay = Duration(seconds: 5);
    final multiplier = 1 << retryCount; // 2^retryCount
    return baseDelay * multiplier;
  }

  // --- Serialization ---

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'receipt_id': receiptId,
      'job_type': jobType.name,
      'status': status.name,
      'retry_count': retryCount,
      'max_retries': maxRetries,
      'next_retry_at': nextRetryAt?.millisecondsSinceEpoch,
      'error_message': errorMessage,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory SyncJob.fromMap(Map<String, dynamic> map) {
    return SyncJob(
      id: map['id'] as String,
      receiptId: map['receipt_id'] as String,
      jobType: JobType.values.firstWhere(
        (e) => e.name == (map['job_type'] as String),
        orElse: () => JobType.uploadImage,
      ),
      status: JobStatus.values.firstWhere(
        (e) => e.name == (map['status'] as String? ?? 'pending'),
        orElse: () => JobStatus.pending,
      ),
      retryCount: (map['retry_count'] as int?) ?? 0,
      maxRetries: (map['max_retries'] as int?) ?? 5,
      nextRetryAt: map['next_retry_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['next_retry_at'] as int)
          : null,
      errorMessage: map['error_message'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int)
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int)
          : DateTime.now(),
    );
  }
}

/// Job types in execution order per receipt
enum JobType {
  uploadImage,     // Upload image to Google Drive
  processReceipt,  // Send image to backend for OCR + LLM parsing
  sheetsAppend,    // Append row to Google Sheets
}

enum JobStatus {
  pending,     // Waiting to run
  inProgress,  // Currently running
  completed,   // Done successfully
  failed,      // Failed (may retry)
}

