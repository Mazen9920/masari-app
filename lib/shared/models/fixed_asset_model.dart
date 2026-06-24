/// A fixed (long-term) asset owned by the business.
///
/// Firestore collection: `fixed_assets/{uid}/assets/{assetId}`
class FixedAsset {
  final String id;
  final String name;
  final String? description;
  final FixedAssetCategory category;
  final DateTime purchaseDate;
  final double purchasePrice;
  final int usefulLifeMonths;
  final DepreciationMethod depreciationMethod;
  final double salvageValue;
  final FixedAssetStatus status;
  final DateTime? disposalDate;
  final double? disposalPrice;
  final double impairmentLoss;
  final String? notes;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<AssetEvent> events;

  const FixedAsset({
    required this.id,
    required this.name,
    this.description,
    required this.category,
    required this.purchaseDate,
    required this.purchasePrice,
    this.usefulLifeMonths = 60,
    this.depreciationMethod = DepreciationMethod.straightLine,
    this.salvageValue = 0,
    this.status = FixedAssetStatus.active,
    this.disposalDate,
    this.disposalPrice,
    this.impairmentLoss = 0,
    this.notes,
    required this.createdAt,
    this.updatedAt,
    this.events = const [],
  });

  // ── Depreciation helpers ──────────────────────────────

  /// Depreciable base = purchase price − salvage value.
  double get depreciableAmount => purchasePrice - salvageValue;

  /// Monthly straight-line depreciation.
  double get monthlyDepreciation {
    if (usefulLifeMonths <= 0) return 0;
    return depreciableAmount / usefulLifeMonths;
  }

  /// How many full months have elapsed since purchase (capped at useful life).
  int get monthsDepreciated {
    final end = disposalDate ?? DateTime.now();
    final months = (end.year - purchaseDate.year) * 12 +
        (end.month - purchaseDate.month);
    return months.clamp(0, usefulLifeMonths);
  }

  /// Total depreciation accumulated to date.
  double get accumulatedDepreciation {
    switch (depreciationMethod) {
      case DepreciationMethod.straightLine:
        return (monthlyDepreciation * monthsDepreciated)
            .clamp(0, depreciableAmount);
      case DepreciationMethod.decliningBalance:
        // Double-declining balance
        final rate = 2.0 / usefulLifeMonths;
        double remaining = purchasePrice;
        double totalDep = 0;
        for (int i = 0; i < monthsDepreciated; i++) {
          final dep = remaining * rate;
          if (remaining - dep < salvageValue) {
            totalDep += remaining - salvageValue;
            break;
          }
          totalDep += dep;
          remaining -= dep;
        }
        return totalDep.clamp(0, depreciableAmount);
    }
  }

  /// Current net book value (accounts for impairment).
  double get netBookValue => (purchasePrice - accumulatedDepreciation - impairmentLoss)
      .clamp(0, purchasePrice);

  /// Gain or loss on disposal/sale (positive = gain, negative = loss).
  double get disposalGainLoss {
    if (disposalPrice == null) return 0;
    return disposalPrice! - netBookValue;
  }

  /// Whether the asset is fully depreciated.
  bool get isFullyDepreciated => monthsDepreciated >= usefulLifeMonths;

  /// Remaining useful life in months.
  int get remainingLifeMonths =>
      (usefulLifeMonths - monthsDepreciated).clamp(0, usefulLifeMonths);

  // ── Serialization ─────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'category': category.name,
        'purchase_date': purchaseDate.toIso8601String(),
        'purchase_price': purchasePrice,
        'useful_life_months': usefulLifeMonths,
        'depreciation_method': depreciationMethod.name,
        'salvage_value': salvageValue,
        'status': status.name,
        'disposal_date': disposalDate?.toIso8601String(),
        'disposal_price': disposalPrice,
        'impairment_loss': impairmentLoss,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
        'events': events.map((e) => e.toJson()).toList(),
      };

  factory FixedAsset.fromJson(Map<String, dynamic> json) {
    return FixedAsset(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      category: FixedAssetCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => FixedAssetCategory.other,
      ),
      purchaseDate: DateTime.parse(json['purchase_date'] as String),
      purchasePrice: (json['purchase_price'] as num?)?.toDouble() ?? 0,
      usefulLifeMonths: (json['useful_life_months'] as num?)?.toInt() ?? 60,
      depreciationMethod: DepreciationMethod.values.firstWhere(
        (m) => m.name == json['depreciation_method'],
        orElse: () => DepreciationMethod.straightLine,
      ),
      salvageValue: (json['salvage_value'] as num?)?.toDouble() ?? 0,
      status: FixedAssetStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => FixedAssetStatus.active,
      ),
      disposalDate: json['disposal_date'] != null
          ? DateTime.parse(json['disposal_date'] as String)
          : null,
      disposalPrice: (json['disposal_price'] as num?)?.toDouble(),
      impairmentLoss: (json['impairment_loss'] as num?)?.toDouble() ?? 0,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      events: (json['events'] as List<dynamic>?)
              ?.map((e) => AssetEvent.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  FixedAsset copyWith({
    String? id,
    String? name,
    String? description,
    FixedAssetCategory? category,
    DateTime? purchaseDate,
    double? purchasePrice,
    int? usefulLifeMonths,
    DepreciationMethod? depreciationMethod,
    double? salvageValue,
    FixedAssetStatus? status,
    DateTime? disposalDate,
    double? disposalPrice,
    double? impairmentLoss,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<AssetEvent>? events,
  }) {
    return FixedAsset(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      usefulLifeMonths: usefulLifeMonths ?? this.usefulLifeMonths,
      depreciationMethod: depreciationMethod ?? this.depreciationMethod,
      salvageValue: salvageValue ?? this.salvageValue,
      status: status ?? this.status,
      disposalDate: disposalDate ?? this.disposalDate,
      disposalPrice: disposalPrice ?? this.disposalPrice,
      impairmentLoss: impairmentLoss ?? this.impairmentLoss,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      events: events ?? this.events,
    );
  }
}

/// A recorded event on a fixed asset (sale, disposal, impairment).
class AssetEvent {
  final String id;
  final AssetEventType type;
  final double amount;
  final DateTime date;
  final String? note;
  final String? transactionId;

  const AssetEvent({
    required this.id,
    required this.type,
    required this.amount,
    required this.date,
    this.note,
    this.transactionId,
  });

  AssetEvent copyWith({String? transactionId}) => AssetEvent(
        id: id,
        type: type,
        amount: amount,
        date: date,
        note: note,
        transactionId: transactionId ?? this.transactionId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'amount': amount,
        'date': date.toIso8601String(),
        'note': note,
        'transaction_id': transactionId,
      };

  factory AssetEvent.fromJson(Map<String, dynamic> json) {
    return AssetEvent(
      id: json['id'] as String? ?? '',
      type: AssetEventType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => AssetEventType.impairment,
      ),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      date: json['date'] != null
          ? DateTime.parse(json['date'] as String)
          : DateTime.now(),
      note: json['note'] as String?,
      transactionId: json['transaction_id'] as String?,
    );
  }
}

enum AssetEventType {
  sale,
  disposal,
  impairment,
  partialDamage;

  String get label {
    switch (this) {
      case sale:
        return 'Sale';
      case disposal:
        return 'Disposal';
      case impairment:
        return 'Impairment';
      case partialDamage:
        return 'Partial Damage';
    }
  }

  String get icon {
    switch (this) {
      case sale:
        return '💰';
      case disposal:
        return '🗑️';
      case impairment:
        return '⚠️';
      case partialDamage:
        return '🔨';
    }
  }
}

// ── Enums ──────────────────────────────────────────────

enum FixedAssetCategory {
  equipment,
  furniture,
  vehicle,
  computer,
  machinery,
  building,
  land,
  other;

  String get label {
    switch (this) {
      case equipment:
        return 'Equipment';
      case furniture:
        return 'Furniture';
      case vehicle:
        return 'Vehicle';
      case computer:
        return 'Computer & IT';
      case machinery:
        return 'Machinery';
      case building:
        return 'Building';
      case land:
        return 'Land';
      case other:
        return 'Other';
    }
  }

  String get icon {
    switch (this) {
      case equipment:
        return '🔧';
      case furniture:
        return '🪑';
      case vehicle:
        return '🚗';
      case computer:
        return '💻';
      case machinery:
        return '⚙️';
      case building:
        return '🏢';
      case land:
        return '🏞️';
      case other:
        return '📦';
    }
  }
}

enum DepreciationMethod {
  straightLine,
  decliningBalance;

  String get label {
    switch (this) {
      case straightLine:
        return 'Straight Line';
      case decliningBalance:
        return 'Declining Balance';
    }
  }
}

enum FixedAssetStatus {
  active,
  disposed,
  sold,
  impaired;

  String get label {
    switch (this) {
      case active:
        return 'Active';
      case disposed:
        return 'Disposed';
      case sold:
        return 'Sold';
      case impaired:
        return 'Impaired';
    }
  }
}
