/// Represents a user's connection to Bosta shipping carrier.
///
/// Stores the encrypted API key (server-side only), sync preferences,
/// and connection status.
///
/// The Bosta API key is stored encrypted in Firestore and accessed
/// exclusively by Cloud Functions — it is intentionally excluded
/// from this client-side model for security.
class BostaConnection {
  final String userId;

  /// Bosta business ID (optional, informational).
  final String? bostaBusinessId;

  /// Whether to auto-sync daily.
  final bool autoSyncEnabled;

  /// Timestamp of the most recent sync completion.
  final DateTime? lastSyncAt;

  /// Summary of the most recent sync result.
  final Map<String, dynamic>? lastSyncResult;

  /// When the Bosta connection was first established.
  final DateTime connectedAt;

  /// Current connection health.
  /// "active" — working normally
  /// "disconnected" — user disconnected
  /// "error" — API key invalid or API errors
  final String status;

  /// Live sync progress (written by CF during sync).
  final BostaSyncProgress? syncProgress;

  /// Pre-computed aggregate stats (written by CF after sync).
  final BostaStats? stats;

  /// Running average fee per shipment (updated at each settlement batch).
  final double? averageBostaFee;

  // ── Dashboard (Cashout API) fields ─────────────────────

  /// Dashboard connection health.
  /// "active" — credentials valid
  /// "auth_failed" — login failed, user must re-enter credentials
  final String? dashboardStatus;

  /// When dashboard_status was last updated.
  final DateTime? dashboardStatusUpdatedAt;

  // ── Cash Flow pre-computed summary fields ──────────────

  /// Sum of all Bosta cashout amounts for this user.
  final double? cfTotalCashouts;

  /// Sum of sale.total for COD orders not yet cashed out.
  final double? cfPendingAr;

  /// Count of COD orders not yet cashed out.
  final int? cfPendingArCount;

  /// Most recent cashout transaction_date.
  final DateTime? cfLastCashoutDate;

  /// When the last cashout sync completed.
  final DateTime? cfLastCashoutSyncAt;

  /// Orders before this date are excluded from AR calculation.
  final DateTime? cfArCutoffDate;

  const BostaConnection({
    required this.userId,
    this.bostaBusinessId,
    this.autoSyncEnabled = true,
    this.lastSyncAt,
    this.lastSyncResult,
    required this.connectedAt,
    this.status = 'active',
    this.syncProgress,
    this.stats,
    this.averageBostaFee,
    this.dashboardStatus,
    this.dashboardStatusUpdatedAt,
    this.cfTotalCashouts,
    this.cfPendingAr,
    this.cfPendingArCount,
    this.cfLastCashoutDate,
    this.cfLastCashoutSyncAt,
    this.cfArCutoffDate,
  });

  // ── Computed ─────────────────────────────────────────────

  bool get isActive => status == 'active';
  bool get isDisconnected => status == 'disconnected';
  bool get hasError => status == 'error';

  /// Whether the dashboard (cashout API) credentials are valid.
  bool get isDashboardActive => dashboardStatus == 'active';
  bool get isDashboardAuthFailed => dashboardStatus == 'auth_failed';
  bool get hasDashboard => dashboardStatus != null;

  // ── copyWith ─────────────────────────────────────────────

  BostaConnection copyWith({
    String? userId,
    String? bostaBusinessId,
    bool? autoSyncEnabled,
    DateTime? lastSyncAt,
    Map<String, dynamic>? lastSyncResult,
    DateTime? connectedAt,
    String? status,
    BostaSyncProgress? syncProgress,
    BostaStats? stats,
    double? averageBostaFee,
    String? dashboardStatus,
    DateTime? dashboardStatusUpdatedAt,
    double? cfTotalCashouts,
    double? cfPendingAr,
    int? cfPendingArCount,
    DateTime? cfLastCashoutDate,
    DateTime? cfLastCashoutSyncAt,
    DateTime? cfArCutoffDate,
  }) {
    return BostaConnection(
      userId: userId ?? this.userId,
      bostaBusinessId: bostaBusinessId ?? this.bostaBusinessId,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastSyncResult: lastSyncResult ?? this.lastSyncResult,
      connectedAt: connectedAt ?? this.connectedAt,
      status: status ?? this.status,
      syncProgress: syncProgress ?? this.syncProgress,
      stats: stats ?? this.stats,
      averageBostaFee: averageBostaFee ?? this.averageBostaFee,
      dashboardStatus: dashboardStatus ?? this.dashboardStatus,
      dashboardStatusUpdatedAt: dashboardStatusUpdatedAt ?? this.dashboardStatusUpdatedAt,
      cfTotalCashouts: cfTotalCashouts ?? this.cfTotalCashouts,
      cfPendingAr: cfPendingAr ?? this.cfPendingAr,
      cfPendingArCount: cfPendingArCount ?? this.cfPendingArCount,
      cfLastCashoutDate: cfLastCashoutDate ?? this.cfLastCashoutDate,
      cfLastCashoutSyncAt: cfLastCashoutSyncAt ?? this.cfLastCashoutSyncAt,
      cfArCutoffDate: cfArCutoffDate ?? this.cfArCutoffDate,
    );
  }

  // ── Serialization ────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        // api_key_encrypted intentionally omitted — managed only by Cloud Functions
        if (bostaBusinessId != null) 'bosta_business_id': bostaBusinessId,
        'auto_sync_enabled': autoSyncEnabled,
        if (lastSyncAt != null)
          'last_sync_at': lastSyncAt!.toIso8601String(),
        if (lastSyncResult != null) 'last_sync_result': lastSyncResult,
        'connected_at': connectedAt.toIso8601String(),
        'status': status,
        if (averageBostaFee != null) 'average_bosta_fee': averageBostaFee,
        // dashboard_email/password_encrypted intentionally omitted — managed by CFs
        if (dashboardStatus != null) 'dashboard_status': dashboardStatus,
        if (dashboardStatusUpdatedAt != null)
          'dashboard_status_updated_at': dashboardStatusUpdatedAt!.toIso8601String(),
        if (cfTotalCashouts != null) 'cf_total_cashouts': cfTotalCashouts,
        if (cfPendingAr != null) 'cf_pending_ar': cfPendingAr,
        if (cfPendingArCount != null) 'cf_pending_ar_count': cfPendingArCount,
        if (cfLastCashoutDate != null)
          'cf_last_cashout_date': cfLastCashoutDate!.toIso8601String(),
        if (cfLastCashoutSyncAt != null)
          'cf_last_cashout_sync_at': cfLastCashoutSyncAt!.toIso8601String(),
        if (cfArCutoffDate != null)
          'cf_ar_cutoff_date': cfArCutoffDate!.toIso8601String(),
      };

  factory BostaConnection.fromJson(Map<String, dynamic> json) {
    return BostaConnection(
      userId: json['user_id'] as String? ?? '',
      // api_key_encrypted intentionally not read — only CFs use it
      bostaBusinessId: json['bosta_business_id'] as String?,
      autoSyncEnabled: json['auto_sync_enabled'] as bool? ?? true,
      lastSyncAt: _parseDateTime(json['last_sync_at']),
      lastSyncResult: json['last_sync_result'] != null
          ? Map<String, dynamic>.from(json['last_sync_result'] as Map)
          : null,
      connectedAt: _parseDateTime(json['connected_at']) ?? DateTime.now(),
      status: json['status'] as String? ?? 'active',
      averageBostaFee: (json['average_bosta_fee'] as num?)?.toDouble(),
      syncProgress: json['sync_progress'] != null
          ? BostaSyncProgress.fromJson(
              Map<String, dynamic>.from(json['sync_progress'] as Map))
          : null,
      stats: json['stats'] != null
          ? BostaStats.fromJson(
              Map<String, dynamic>.from(json['stats'] as Map))
          : null,
      dashboardStatus: json['dashboard_status'] as String?,
      dashboardStatusUpdatedAt: _parseDateTime(json['dashboard_status_updated_at']),
      cfTotalCashouts: (json['cf_total_cashouts'] as num?)?.toDouble(),
      cfPendingAr: (json['cf_pending_ar'] as num?)?.toDouble(),
      cfPendingArCount: (json['cf_pending_ar_count'] as num?)?.toInt(),
      cfLastCashoutDate: _parseDateTime(json['cf_last_cashout_date']),
      cfLastCashoutSyncAt: _parseDateTime(json['cf_last_cashout_sync_at']),
      cfArCutoffDate: _parseDateTime(json['cf_ar_cutoff_date']),
    );
  }

  /// Parses a Firestore field that may be a Timestamp, ISO-8601 String,
  /// or null into a DateTime.
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      // ignore: avoid_dynamic_calls
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {}
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {}
    }
    return null;
  }
}

/// Live sync progress written by Cloud Functions during sync.
class BostaSyncProgress {
  final String phase; // catalog, settlement, stats, done
  final int currentPage;
  final int totalPages;
  final int processedCount;
  final int cataloged;
  final int newExpenses;
  final DateTime? startedAt;
  final int elapsedMs;
  final int settlementTotal;
  final int settlementDone;

  const BostaSyncProgress({
    required this.phase,
    this.currentPage = 0,
    this.totalPages = 0,
    this.processedCount = 0,
    this.cataloged = 0,
    this.newExpenses = 0,
    this.startedAt,
    this.elapsedMs = 0,
    this.settlementTotal = 0,
    this.settlementDone = 0,
  });

  bool get isDone => phase == 'done';
  bool get isCatalog => phase == 'catalog';
  bool get isSettlement => phase == 'settlement';

  double get progressPercent {
    if (phase == 'settlement' && settlementTotal > 0) {
      return (settlementDone / settlementTotal).clamp(0.0, 1.0);
    }
    if (totalPages <= 0) return 0;
    return (currentPage / totalPages).clamp(0.0, 1.0);
  }

  /// Estimated seconds remaining based on current progress rate.
  int get estimatedSecondsRemaining {
    if (elapsedMs <= 0) return 0;
    final percent = progressPercent;
    if (percent <= 0) return 0;
    final totalEstMs = elapsedMs / percent;
    return ((totalEstMs - elapsedMs) / 1000).ceil().clamp(0, 600);
  }

  factory BostaSyncProgress.fromJson(Map<String, dynamic> json) {
    return BostaSyncProgress(
      phase: json['phase'] as String? ?? 'done',
      currentPage: (json['current_page'] as num?)?.toInt() ?? 0,
      totalPages: (json['total_pages'] as num?)?.toInt() ?? 0,
      processedCount: (json['processed_count'] as num?)?.toInt() ?? 0,
      cataloged: (json['cataloged'] as num?)?.toInt() ?? 0,
      newExpenses: (json['new_expenses'] as num?)?.toInt() ?? 0,
      startedAt: BostaConnection._parseDateTime(json['started_at']),
      elapsedMs: (json['elapsed_ms'] as num?)?.toInt() ?? 0,
      settlementTotal: (json['settlement_total'] as num?)?.toInt() ?? 0,
      settlementDone: (json['settlement_done'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Pre-computed aggregate stats for a user's Bosta shipments.
/// Written by Cloud Functions after sync completion.
class BostaStats {
  final int totalShipments;
  final int matchedCount;
  final int unlinkedCount;
  final int settledCount;
  final int awaitingCount;
  final double totalFees;
  final DateTime? computedAt;

  const BostaStats({
    this.totalShipments = 0,
    this.matchedCount = 0,
    this.unlinkedCount = 0,
    this.settledCount = 0,
    this.awaitingCount = 0,
    this.totalFees = 0,
    this.computedAt,
  });

  factory BostaStats.fromJson(Map<String, dynamic> json) {
    return BostaStats(
      totalShipments: (json['total_shipments'] as num?)?.toInt() ?? 0,
      matchedCount: (json['matched_count'] as num?)?.toInt() ?? 0,
      unlinkedCount: (json['unlinked_count'] as num?)?.toInt() ?? 0,
      settledCount: (json['settled_count'] as num?)?.toInt() ?? 0,
      awaitingCount: (json['awaiting_count'] as num?)?.toInt() ?? 0,
      totalFees: (json['total_fees'] as num?)?.toDouble() ?? 0,
      computedAt: BostaConnection._parseDateTime(json['computed_at']),
    );
  }
}
