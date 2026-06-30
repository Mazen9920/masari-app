import 'package:flutter_test/flutter_test.dart';
import 'package:revvo_app/shared/utils/equity_recon.dart';
import 'package:revvo_app/shared/models/fixed_asset_model.dart';

void main() {
  group('reconcileEquity', () {
    test('auto-capital: always balances by construction', () {
      final r = reconcileEquity(
        netEquity: 1000,
        openingCapital: 0,
        hasManualCapital: false,
        retainedEarnings: 600,
        currentNetIncome: 200,
        ownerContributions: 0,
        ownerWithdrawals: 0,
      );
      expect(r.unexplainedDifference, 0);
      // Auto capital is back-derived = netEquity − retained − current.
      expect(r.effectiveCapital, 200);
    });

    test('auto-capital with owner flows: capital excludes them, still balances',
        () {
      final r = reconcileEquity(
        netEquity: 1000,
        openingCapital: 0,
        hasManualCapital: false,
        retainedEarnings: 400,
        currentNetIncome: 100,
        ownerContributions: 300,
        ownerWithdrawals: 50,
      );
      // capital = 1000 − 400 − 100 − 300 + 50 = 250
      expect(r.effectiveCapital, 250);
      expect(r.unexplainedDifference, 0);
    });

    test('manual capital, clean books → no unexplained difference', () {
      final r = reconcileEquity(
        netEquity: 84023 + 300000 + 100000,
        openingCapital: 84023,
        hasManualCapital: true,
        retainedEarnings: 300000,
        currentNetIncome: 100000,
        ownerContributions: 0,
        ownerWithdrawals: 0,
      );
      expect(r.unexplainedDifference, 0);
      expect(r.effectiveCapital, 84023);
    });

    test('manual capital + untracked cash → surfaces the real gap', () {
      // Net equity is 5,000 higher than capital + profit can explain.
      final r = reconcileEquity(
        netEquity: 84023 + 300000 + 100000 + 5000,
        openingCapital: 84023,
        hasManualCapital: true,
        retainedEarnings: 300000,
        currentNetIncome: 100000,
        ownerContributions: 0,
        ownerWithdrawals: 0,
      );
      expect(r.unexplainedDifference, 5000);
    });

    test('manual capital + owner contributions/withdrawals net out', () {
      final r = reconcileEquity(
        netEquity: 100000 + 50000 + 20000 + 30000 - 10000,
        openingCapital: 100000,
        hasManualCapital: true,
        retainedEarnings: 50000,
        currentNetIncome: 20000,
        ownerContributions: 30000,
        ownerWithdrawals: 10000,
      );
      expect(r.unexplainedDifference, 0);
    });

    test('opening deficit explains the gap WITHOUT negative capital (RPE case)',
        () {
      // RPE: net worth 325,994; contributed capital stays positive (84,023);
      // the −174,696 pre-books debt sits in opening retained earnings.
      final r = reconcileEquity(
        netEquity: 325994,
        openingCapital: 84023,
        hasManualCapital: true,
        retainedEarnings: 329153,
        currentNetIncome: 87514,
        ownerContributions: 0,
        ownerWithdrawals: 0,
        openingRetainedEarnings: -174696,
      );
      expect(r.effectiveCapital, 84023); // positive, not buried
      expect(r.openingRetainedEarnings, -174696);
      expect(r.unexplainedDifference, 0); // balances
    });

    test('opening retained earnings shifts capital, not the unexplained gap',
        () {
      // Splitting the opening position between capital and opening retained
      // earnings keeps the books balanced either way.
      final r = reconcileEquity(
        netEquity: 325994,
        openingCapital: 0, // owners put in nothing; all sits in opening RE
        hasManualCapital: true,
        retainedEarnings: 329153,
        currentNetIncome: 87514,
        ownerContributions: 0,
        ownerWithdrawals: 0,
        openingRetainedEarnings: -90673,
      );
      expect(r.unexplainedDifference, 0);
    });

    test('auto-capital unaffected by a stray opening RE (back-derives correctly)',
        () {
      final r = reconcileEquity(
        netEquity: 1000,
        openingCapital: 0,
        hasManualCapital: false,
        retainedEarnings: 600,
        currentNetIncome: 200,
        ownerContributions: 0,
        ownerWithdrawals: 0,
        openingRetainedEarnings: 150,
      );
      // capital = 1000 − 150 − 600 − 200 = 50; still balances.
      expect(r.effectiveCapital, 50);
      expect(r.unexplainedDifference, 0);
    });
  });

  group('FixedAsset.accumulatedDepreciationAsOf (period split)', () {
    // 12,000 asset, 0 salvage, 12-month life → 1,000/month straight-line.
    final asset = FixedAsset(
      id: 'a1',
      name: 'Laptop',
      category: FixedAssetCategory.equipment,
      purchaseDate: DateTime(2026, 1, 1),
      purchasePrice: 12000,
      usefulLifeMonths: 12,
      salvageValue: 0,
      createdAt: DateTime(2026, 1, 1),
    );

    test('accumulates 1,000/month straight-line', () {
      expect(asset.accumulatedDepreciationAsOf(DateTime(2026, 1, 1)), 0);
      expect(asset.accumulatedDepreciationAsOf(DateTime(2026, 4, 1)), 3000);
      expect(asset.accumulatedDepreciationAsOf(DateTime(2026, 7, 1)), 6000);
    });

    test('caps at depreciable amount past useful life', () {
      expect(asset.accumulatedDepreciationAsOf(DateTime(2028, 1, 1)), 12000);
    });

    test('period split: prior vs current = current-period expense', () {
      final periodStart = DateTime(2026, 4, 1); // 3 months in
      final asOf = DateTime(2026, 7, 1); // 6 months in
      final prior = asset.accumulatedDepreciationAsOf(periodStart);
      final total = asset.accumulatedDepreciationAsOf(asOf);
      expect(prior, 3000);
      expect(total - prior, 3000); // current-period depreciation expense
    });
  });
}
