import 'package:flutter/material.dart';
import 'package:taxi_driver_app/models/driver.dart';
import 'package:taxi_driver_app/models/driver_tier.dart';

/// Widget for displaying driver tier badge
class TierBadgeWidget extends StatelessWidget {
  final Driver driver;

  const TierBadgeWidget({Key? key, required this.driver}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tier = driver.tier;
    final tierColor = _getTierColor(tier);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: tierColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tierColor, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(driver.tierIcon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text(
            '${driver.tierDisplayName} Driver',
            style: TextStyle(
              color: tierColor,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Color _getTierColor(DriverTier tier) {
    switch (tier) {
      case DriverTier.platinum:
        return const Color(0xFFE5E4E2);
      case DriverTier.gold:
        return const Color(0xFFFFD700);
      case DriverTier.silver:
        return const Color(0xFFC0C0C0);
      case DriverTier.bronze:
        return const Color(0xFFCD7F32);
    }
  }
}

/// Widget for displaying driver metrics dashboard
class MetricsDashboardWidget extends StatelessWidget {
  final Driver driver;

  const MetricsDashboardWidget({Key? key, required this.driver})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (driver.metrics == null) {
      return const SizedBox.shrink();
    }

    final metrics = driver.metrics!;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Performance Metrics',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (metrics.isInGracePeriod)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Grace Period',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Acceptance Rate
            _buildMetricRow(
              'Acceptance Rate',
              metrics.formattedAcceptanceRate,
              metrics.acceptanceRate / 100,
              Colors.green,
            ),
            const SizedBox(height: 12),

            // Reliability Score
            _buildMetricRow(
              'Reliability Score',
              metrics.formattedReliabilityScore,
              metrics.reliabilityScore / 100,
              Colors.blue,
            ),
            const SizedBox(height: 12),

            // Cancellation Rate
            _buildMetricRow(
              'Cancellation Rate',
              metrics.formattedCancellationRate,
              metrics.cancellationRate / 100,
              Colors.orange,
            ),

            const Divider(height: 24),

            // Trip Statistics
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn(
                  'Completed',
                  '${metrics.tripsCompleted}',
                  Icons.check_circle,
                  Colors.green,
                ),
                _buildStatColumn(
                  'Accepted',
                  '${metrics.tripsAccepted}',
                  Icons.thumb_up,
                  Colors.blue,
                ),
                _buildStatColumn(
                  'Cancelled',
                  '${metrics.tripsCancelled}',
                  Icons.cancel,
                  Colors.red,
                ),
              ],
            ),

            // At Risk Warning
            if (metrics.isAtRisk) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your performance is at risk. Maintain ${driver.tier.minAcceptanceRate}% acceptance rate to keep ${driver.tierDisplayName} status.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Next Tier Requirements
            if (!metrics.isInGracePeriod &&
                driver.tier != DriverTier.platinum) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.trending_up, color: Colors.blue, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Next Tier',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      metrics.getNextTierRequirements(driver.rating),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(
    String label,
    String value,
    double progress,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          backgroundColor: Colors.grey[200],
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 8,
        ),
      ],
    );
  }

  Widget _buildStatColumn(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}

/// Widget for displaying tier benefits
class TierBenefitsWidget extends StatelessWidget {
  final Driver driver;

  const TierBenefitsWidget({Key? key, required this.driver}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tier = driver.tier;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(tier.icon, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Text(
                  '${tier.displayName} Benefits',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              tier.benefits,
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.priority_high, size: 16, color: Colors.blue),
                const SizedBox(width: 4),
                Text(
                  'Priority Bonus: +${tier.priorityBonus.toStringAsFixed(0)} points',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.attach_money, size: 16, color: Colors.green),
                const SizedBox(width: 4),
                Text(
                  'Earnings: ${((tier.bonusMultiplier - 1) * 100).toStringAsFixed(0)}% bonus',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
