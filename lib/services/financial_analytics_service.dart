import 'dart:math' as math;
import 'package:intl/intl.dart';
import '../core/models/models.dart';
import '../core/state/app_data.dart';

/// Comprehensive financial metrics model for executive analytics.
class FinancialMetrics {
  final String monthKey;
  final int totalUnits;
  final int occupiedUnits;
  final int vacantUnits;
  final double occupancyRate; // 0 - 100%
  final double grossPotentialRent; // Rent if 100% occupied
  final double vacancyLoss;

  final double grossRevenue; // Rent collected + confirmed deposits
  final double totalOperatingExpenses;
  final double netOperatingIncome; // NOI = Gross Revenue - OpEx
  final double operatingExpenseRatio; // OER% = (OpEx / Gross Revenue) * 100
  final double operatingMargin; // Margin% = (NOI / Gross Revenue) * 100

  final double scheduledRent;
  final double collectedRent;
  final double pendingRent;
  final double collectionEfficiency; // (Collected / Scheduled) * 100
  final double onTimeRate; // % paid on or before dueDate

  final double? revenueChangePct; // vs prior month
  final double? expenseChangePct;
  final double? noiChangePct;

  const FinancialMetrics({
    required this.monthKey,
    required this.totalUnits,
    required this.occupiedUnits,
    required this.vacantUnits,
    required this.occupancyRate,
    required this.grossPotentialRent,
    required this.vacancyLoss,
    required this.grossRevenue,
    required this.totalOperatingExpenses,
    required this.netOperatingIncome,
    required this.operatingExpenseRatio,
    required this.operatingMargin,
    required this.scheduledRent,
    required this.collectedRent,
    required this.pendingRent,
    required this.collectionEfficiency,
    required this.onTimeRate,
    this.revenueChangePct,
    this.expenseChangePct,
    this.noiChangePct,
  });
}

/// A single month forward-looking cash flow forecast node.
class ProjectedMonthCashFlow {
  final String monthKey; // 'YYYY-MM'
  final String monthLabel; // 'Nov 2026'
  final double projectedInflow; // Scheduled rent from active leases
  final double projectedOutflow; // Estimated operating & recurring expenses
  final double projectedNet; // Inflow - Outflow
  final double cumulativeReserve; // Running forecasted cash balance
  final int activeTenantsCount;
  final int expiringLeasesCount;

  const ProjectedMonthCashFlow({
    required this.monthKey,
    required this.monthLabel,
    required this.projectedInflow,
    required this.projectedOutflow,
    required this.projectedNet,
    required this.cumulativeReserve,
    required this.activeTenantsCount,
    required this.expiringLeasesCount,
  });
}

/// Lease renewal pipeline item highlighting upcoming expirations.
class LeaseExpiryItem {
  final Tenant tenant;
  final int daysRemaining;
  final DateTime expiryDate;
  final String urgency; // 'critical' (<=30d), 'warning' (31-60d), 'healthy' (>60d)

  const LeaseExpiryItem({
    required this.tenant,
    required this.daysRemaining,
    required this.expiryDate,
    required this.urgency,
  });
}

/// Complete predictive forecast result bundle.
class CashFlowForecastResult {
  final List<ProjectedMonthCashFlow> projections;
  final List<LeaseExpiryItem> upcomingExpirations;
  final double totalProjectedInflow;
  final double totalProjectedOutflow;
  final double totalProjectedNet;
  final double averageMonthlyInflow;
  final double averageMonthlyOutflow;
  final double baselineReserve;

  const CashFlowForecastResult({
    required this.projections,
    required this.upcomingExpirations,
    required this.totalProjectedInflow,
    required this.totalProjectedOutflow,
    required this.totalProjectedNet,
    required this.averageMonthlyInflow,
    required this.averageMonthlyOutflow,
    required this.baselineReserve,
  });
}

/// Service computing executive financial metrics, NOI, OER, and predictive cash flow forecasts.
class FinancialAnalyticsService {
  /// Computes comprehensive financial indicators for a given month and its prior comparison.
  static FinancialMetrics computeMetrics({
    required AppDataState state,
    required int year,
    required int month,
  }) {
    final monthKey = '$year-${month.toString().padLeft(2, '0')}';
    final priorDate = DateTime(year, month - 1);
    final priorMonthKey =
        '${priorDate.year}-${priorDate.month.toString().padLeft(2, '0')}';

    final currentData = _computeRawMonth(state, monthKey);
    final priorData = _computeRawMonth(state, priorMonthKey);

    double? calcChange(double curr, double prior) {
      if (prior <= 0) return null;
      return ((curr - prior) / prior) * 100.0;
    }

    return FinancialMetrics(
      monthKey: monthKey,
      totalUnits: currentData['totalUnits'] as int,
      occupiedUnits: currentData['occupiedUnits'] as int,
      vacantUnits: currentData['vacantUnits'] as int,
      occupancyRate: currentData['occupancyRate'] as double,
      grossPotentialRent: currentData['grossPotentialRent'] as double,
      vacancyLoss: currentData['vacancyLoss'] as double,
      grossRevenue: currentData['grossRevenue'] as double,
      totalOperatingExpenses: currentData['totalOperatingExpenses'] as double,
      netOperatingIncome: currentData['netOperatingIncome'] as double,
      operatingExpenseRatio: currentData['operatingExpenseRatio'] as double,
      operatingMargin: currentData['operatingMargin'] as double,
      scheduledRent: currentData['scheduledRent'] as double,
      collectedRent: currentData['collectedRent'] as double,
      pendingRent: currentData['pendingRent'] as double,
      collectionEfficiency: currentData['collectionEfficiency'] as double,
      onTimeRate: currentData['onTimeRate'] as double,
      revenueChangePct: calcChange(
        currentData['grossRevenue'] as double,
        priorData['grossRevenue'] as double,
      ),
      expenseChangePct: calcChange(
        currentData['totalOperatingExpenses'] as double,
        priorData['totalOperatingExpenses'] as double,
      ),
      noiChangePct: calcChange(
        currentData['netOperatingIncome'] as double,
        priorData['netOperatingIncome'] as double,
      ),
    );
  }

  static Map<String, dynamic> _computeRawMonth(AppDataState state, String monthKey) {
    // 1. Tenants & Units (scoped to active property selection)
    final allTenants = state.scopedTenants;
    final parts = monthKey.split('-');
    final monthYear = int.tryParse(parts.isNotEmpty ? parts[0] : '') ??
        DateTime.now().year;
    final monthNumber = int.tryParse(parts.length > 1 ? parts[1] : '') ??
        DateTime.now().month;
    final monthStart = DateTime(monthYear, monthNumber, 1);
    final monthEnd = DateTime(monthYear, monthNumber + 1, 0);

    bool coveredByLease(Tenant t) {
      final start = DateTime.tryParse(t.leaseStartDate?.trim() ?? '');
      final end = DateTime.tryParse(t.leaseEndDate?.trim() ?? '');
      if (start == null && end == null) return false;
      if (start != null && start.isAfter(monthEnd)) return false;
      if (end != null && end.isBefore(monthStart)) return false;
      return true;
    }

    bool hasLeaseDates(Tenant t) =>
        (t.leaseStartDate?.trim().isNotEmpty ?? false) ||
        (t.leaseEndDate?.trim().isNotEmpty ?? false);

    // Occupied units: genuinely active for the selected month.
    bool occupiedInMonth(Tenant t) {
      if (hasLeaseDates(t)) return coveredByLease(t);
      return t.status.toLowerCase().trim() == 'active';
    }

    // Unit denominator: include legacy tenants with unknown history (anything
    // not explicitly inactive) so unit counts stay stable.
    bool countedInMonth(Tenant t) {
      if (hasLeaseDates(t)) return coveredByLease(t);
      return t.status.toLowerCase().trim() != 'inactive';
    }

    final activeTenants = allTenants.where(occupiedInMonth).toList();

    // Unique unit count: use the roster as of the selected month so historical
    // occupancy is not computed from today's tenants.
    final currentTenants = allTenants.where(countedInMonth).toList();
    final distinctUnits = currentTenants.map((t) => t.unit.trim()).where((u) => u.isNotEmpty).toSet();
    final configuredUnits = state.activeProperty?.totalUnits ?? 0;
    final totalUnits = math.max(
      configuredUnits,
      math.max(distinctUnits.length, currentTenants.length),
    );
    final occupiedUnits = activeTenants.length;
    final vacantUnits = math.max(0, totalUnits - occupiedUnits);
    final occupancyRate = totalUnits > 0 ? (occupiedUnits / totalUnits) * 100.0 : 0.0;

    // Gross Potential Rent: rent of all occupied + estimated rent for vacant units
    final averageRent = occupiedUnits > 0
        ? activeTenants.fold<double>(0.0, (sum, t) => sum + t.rentAmount) / occupiedUnits
        : 1000.0;
    final grossPotentialRent =
        activeTenants.fold<double>(0.0, (sum, t) => sum + t.rentAmount) + (vacantUnits * averageRent);
    final vacancyLoss = vacantUnits * averageRent;

    // 2. Payments for the month (scoped)
    final payments = state.scopedPayments.where((p) {
      final pMonth = p.paidForMonth ?? p.displayMonth;
      return pMonth == monthKey;
    }).toList();

    final scheduledRent = activeTenants.fold<double>(0.0, (sum, t) => sum + t.rentAmount);
    double collectedRent = 0.0;
    double pendingRent = 0.0;
    int onTimeCount = 0;
    int totalPaidCount = 0;

    for (final p in payments) {
      if (p.status.toLowerCase().trim() == 'paid') {
        collectedRent += p.amount;
        totalPaidCount++;
        // On time check: paidDate <= dueDate
        if (p.paidDate != null && p.dueDate != null) {
          try {
            final pd = DateTime.parse(p.paidDate!);
            final dd = DateTime.parse(p.dueDate!);
            if (!pd.isAfter(dd)) onTimeCount++;
          } catch (_) {
            onTimeCount++;
          }
        } else {
          onTimeCount++;
        }
      } else {
        pendingRent += p.amount;
      }
    }

    final collectionEfficiency =
        scheduledRent > 0 ? (collectedRent / scheduledRent) * 100.0 : (collectedRent > 0 ? 100.0 : 0.0);
    final onTimeRate =
        totalPaidCount > 0 ? (onTimeCount / totalPaidCount) * 100.0 : 100.0;

    // 3. Bank Deposits for month. Deposits linked to payments already counted
    // above are cash movements, not additional revenue.
    final paidPaymentIds = <String>{
      for (final p in state.scopedPayments)
        if (p.status.toLowerCase().trim() == 'paid') p.id,
    };
    final deposits = state.scopedBankDeposits.where((d) {
      final dMonth = d.depositDate.length >= 7 ? d.depositDate.substring(0, 7) : '';
      if (dMonth != monthKey || d.status.toLowerCase().trim() != 'confirmed') {
        return false;
      }
      return !d.linkedPaymentIds.any(paidPaymentIds.contains);
    }).fold<double>(0.0, (sum, d) => sum + d.amount);

    final grossRevenue = collectedRent + deposits;

    // 4. Operating Expenses (scoped)
    final expenses = state.scopedExpenses.where((e) {
      final eMonth = e.expenseForMonth ?? (e.date.length >= 7 ? e.date.substring(0, 7) : '');
      return eMonth == monthKey;
    }).fold<double>(0.0, (sum, e) => sum + e.amount);

    // Paid Work Orders for the month (scoped)
    final workOrderCosts = state.scopedWorkOrders.where((w) {
      final wDate = w.completedAt ?? w.createdAt;
      final wMonth = wDate.length >= 7 ? wDate.substring(0, 7) : '';
      return wMonth == monthKey && w.status.toLowerCase().trim() == 'completed';
    }).fold<double>(0.0, (sum, w) => sum + (w.workerCost ?? 0.0) + (w.productPrice ?? 0.0));

    final totalOperatingExpenses = expenses + workOrderCosts;
    final netOperatingIncome = grossRevenue - totalOperatingExpenses;
    final operatingExpenseRatio = grossRevenue > 0
        ? (totalOperatingExpenses / grossRevenue) * 100.0
        : (totalOperatingExpenses > 0 ? 100.0 : 0.0);
    final operatingMargin = grossRevenue > 0
        ? (netOperatingIncome / grossRevenue) * 100.0
        : 0.0;

    return {
      'totalUnits': totalUnits,
      'occupiedUnits': occupiedUnits,
      'vacantUnits': vacantUnits,
      'occupancyRate': occupancyRate,
      'grossPotentialRent': grossPotentialRent,
      'vacancyLoss': vacancyLoss,
      'grossRevenue': grossRevenue,
      'totalOperatingExpenses': totalOperatingExpenses,
      'netOperatingIncome': netOperatingIncome,
      'operatingExpenseRatio': operatingExpenseRatio,
      'operatingMargin': operatingMargin,
      'scheduledRent': scheduledRent,
      'collectedRent': collectedRent,
      'pendingRent': pendingRent,
      'collectionEfficiency': collectionEfficiency,
      'onTimeRate': onTimeRate,
    };
  }

  /// Projects monthly cash flows forward for the next 6 or 12 months.
  /// Can be anchored to an explicit start year & month (syncs with user selection).
  static CashFlowForecastResult computeCashFlowForecast({
    required AppDataState state,
    int monthsAhead = 6,
    int? startYear,
    int? startMonth,
    double estimatedVacancyDiscountPct = 3.0, // Historical default allowance
  }) {
    final now = DateTime.now();
    final anchorDate = DateTime(
      startYear ?? now.year,
      startMonth ?? now.month,
      1,
    );
    final activeTenants =
        state.scopedTenants.where((t) => t.status.toLowerCase().trim() == 'active').toList();

    // 1. Calculate baseline recurring monthly operating expenses from past 3 months
    double pastExpensesSum = 0.0;
    int monthsCounted = 0;
    for (int i = 0; i < 3; i++) {
      final mDate = DateTime(anchorDate.year, anchorDate.month - i, 1);
      final mKey = '${mDate.year}-${mDate.month.toString().padLeft(2, '0')}';
      final mExpenses = state.scopedExpenses
          .where((e) => (e.expenseForMonth ?? (e.date.length >= 7 ? e.date.substring(0, 7) : '')) == mKey)
          .fold<double>(0.0, (sum, e) => sum + e.amount);
      final mWorkOrders = state.scopedWorkOrders
          .where((w) {
            final wDate = w.completedAt ?? w.createdAt;
            final wMonth = wDate.length >= 7 ? wDate.substring(0, 7) : '';
            return wMonth == mKey && w.status.toLowerCase().trim() == 'completed';
          })
          .fold<double>(0.0, (sum, w) => sum + (w.workerCost ?? 0.0) + (w.productPrice ?? 0.0));
      final totalMonthlyExp = mExpenses + mWorkOrders;
      if (totalMonthlyExp > 0) {
        pastExpensesSum += totalMonthlyExp;
        monthsCounted++;
      }
    }
    double baselineMonthlyExpenses = 0.0;
    if (monthsCounted > 0) {
      baselineMonthlyExpenses = pastExpensesSum / monthsCounted;
    } else if (state.scopedExpenses.isNotEmpty) {
      // Fallback: average across all available scoped expenses
      final totalExp = state.scopedExpenses.fold<double>(0.0, (s, e) => s + e.amount);
      final uniqueMonths = state.scopedExpenses
          .map((e) => e.expenseForMonth ?? (e.date.length >= 7 ? e.date.substring(0, 7) : ''))
          .where((k) => k.isNotEmpty)
          .toSet();
      baselineMonthlyExpenses = uniqueMonths.isNotEmpty ? totalExp / uniqueMonths.length : totalExp;
    }

    // 2. Upcoming Lease Expirations. For the current month (or a past month),
    // count down from today rather than from the 1st, otherwise a lease ending
    // later this month is misreported as already expired.
    final anchorMonth = DateTime(anchorDate.year, anchorDate.month, 1);
    final currentMonth = DateTime(now.year, now.month, 1);
    final countdownFrom = anchorMonth.isAfter(currentMonth) ? anchorDate : now;
    final upcomingExpirations = <LeaseExpiryItem>[];
    for (final t in activeTenants) {
      if (t.leaseEndDate != null && t.leaseEndDate!.trim().isNotEmpty) {
        final end = DateTime.tryParse(t.leaseEndDate!.trim());
        if (end != null) {
          final diff = end.difference(countdownFrom).inDays;
          if (diff >= -30 && diff <= 120) {
            String urgency = 'healthy';
            if (diff <= 30) {
              urgency = 'critical';
            } else if (diff <= 60) {
              urgency = 'warning';
            }
            upcomingExpirations.add(
              LeaseExpiryItem(
                tenant: t,
                daysRemaining: diff,
                expiryDate: end,
                urgency: urgency,
              ),
            );
          }
        }
      }
    }
    upcomingExpirations.sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));

    // 3. Current liquid reserve (net historical cash balance for the active scope)
    final totalCollected = state.scopedPayments
        .where((p) => p.status.toLowerCase().trim() == 'paid')
        .fold<double>(0.0, (sum, p) => sum + p.amount);
    final totalExpenses = state.scopedExpenses
        .fold<double>(0.0, (sum, e) => sum + e.amount);
    final totalWorkOrders = state.scopedWorkOrders
        .where((w) => w.status.toLowerCase().trim() == 'completed')
        .fold<double>(0.0, (sum, w) => sum + (w.workerCost ?? 0.0) + (w.productPrice ?? 0.0));
    final netHistoricalCash = math.max(0.0, totalCollected - (totalExpenses + totalWorkOrders));
    double runningReserve = netHistoricalCash;

    final projections = <ProjectedMonthCashFlow>[];
    double totalInflow = 0.0;
    double totalOutflow = 0.0;

    for (int i = 1; i <= monthsAhead; i++) {
      final targetDate = DateTime(anchorDate.year, anchorDate.month + i, 1);
      final monthKey = '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}';
      final monthLabel = DateFormat('MMM yyyy').format(targetDate);

      // Check which tenants are expected to still be active in targetDate
      int activeCountInMonth = 0;
      int expiringCountInMonth = 0;
      double scheduledRentForMonth = 0.0;

      for (final t in activeTenants) {
        bool isActiveInMonth = true;
        // Check start date
        if (t.leaseStartDate != null && t.leaseStartDate!.trim().isNotEmpty) {
          final start = DateTime.tryParse(t.leaseStartDate!.trim());
          if (start != null && start.isAfter(DateTime(targetDate.year, targetDate.month + 1, 0))) {
            // Tenant starts in a future month beyond targetDate
            continue;
          }
        }

        if (t.leaseEndDate != null && t.leaseEndDate!.trim().isNotEmpty) {
          final end = DateTime.tryParse(t.leaseEndDate!.trim());
          if (end != null) {
            final monthStart = DateTime(targetDate.year, targetDate.month, 1);
            if (end.isBefore(monthStart)) {
              if (end.isBefore(anchorDate)) {
                // Lease already expired before the forecast window: gone.
                continue;
              }
              // Ends between today and the projected month: 75% renewal chance,
              // but drop entirely past 12 months of renewal uncertainty.
              if (monthStart.difference(end).inDays <= 366) {
                scheduledRentForMonth += t.rentAmount * 0.75;
                isActiveInMonth = false;
              } else {
                continue;
              }
            } else if (end.year == targetDate.year && end.month == targetDate.month) {
              expiringCountInMonth++;
              scheduledRentForMonth += t.rentAmount;
            } else {
              scheduledRentForMonth += t.rentAmount;
            }
          } else {
            scheduledRentForMonth += t.rentAmount;
          }
        } else {
          scheduledRentForMonth += t.rentAmount;
        }

        if (isActiveInMonth) activeCountInMonth++;
      }

      // Net projected inflow applies small vacancy/delay discount
      final discountFactor = (100.0 - estimatedVacancyDiscountPct) / 100.0;
      final projectedInflow = scheduledRentForMonth * discountFactor;

      // Seasonal adjustment for expenses (e.g. winter heating / summer HVAC)
      double seasonalMultiplier = 1.0;
      if (targetDate.month == 1 || targetDate.month == 12 || targetDate.month == 7 || targetDate.month == 8) {
        seasonalMultiplier = 1.15; // +15% HVAC/utility surge
      }
      final projectedOutflow = baselineMonthlyExpenses * seasonalMultiplier;

      final projectedNet = projectedInflow - projectedOutflow;
      runningReserve += projectedNet;
      totalInflow += projectedInflow;
      totalOutflow += projectedOutflow;

      projections.add(
        ProjectedMonthCashFlow(
          monthKey: monthKey,
          monthLabel: monthLabel,
          projectedInflow: projectedInflow,
          projectedOutflow: projectedOutflow,
          projectedNet: projectedNet,
          cumulativeReserve: runningReserve,
          activeTenantsCount: activeCountInMonth,
          expiringLeasesCount: expiringCountInMonth,
        ),
      );
    }

    final totalNet = totalInflow - totalOutflow;

    return CashFlowForecastResult(
      projections: projections,
      upcomingExpirations: upcomingExpirations,
      totalProjectedInflow: totalInflow,
      totalProjectedOutflow: totalOutflow,
      totalProjectedNet: totalNet,
      averageMonthlyInflow: monthsAhead > 0 ? totalInflow / monthsAhead : 0.0,
      averageMonthlyOutflow: monthsAhead > 0 ? totalOutflow / monthsAhead : 0.0,
      baselineReserve: netHistoricalCash,
    );
  }
}
