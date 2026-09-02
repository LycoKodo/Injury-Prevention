import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tennis_form/models/feedback.dart' as fb;
import 'package:tennis_form/models/kinetic_chain.dart';
import 'package:tennis_form/models/swing_report.dart';
import 'package:tennis_form/theme/app_theme.dart';
import 'package:tennis_form/widgets/swing_report_card.dart';

void main() {
  testWidgets('SwingReportCard shows scores and feedback titles', (tester) async {
    final report = SwingReport(
      id: 1,
      tContact: 10.6,
      efficiencyScore: 74,
      injuryRiskScore: 31,
      forceDistribution: const {'legs': 18, 'hips': 22, 'trunk': 20, 'shoulder': 22, 'arm': 18},
      idealDistribution: const {'legs': 20, 'hips': 25, 'trunk': 20, 'shoulder': 20, 'arm': 15},
      kineticChain: const KineticChain(sequencingOk: true, lagHipToShoulderMs: 70, lagShoulderToArmMs: 60),
      feedback: const [
        fb.Feedback(
          severity: fb.FeedbackSeverity.good,
          joint: 'elbow',
          title: 'Great extension',
          detail: 'Nice arm extension at contact.',
        ),
        fb.Feedback(
          severity: fb.FeedbackSeverity.danger,
          joint: 'lower_back',
          title: 'Excessive trunk lean',
          detail: 'Trunk lateral flexion exceeded 20 degrees.',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SingleChildScrollView(child: SwingReportCard(report: report)),
        ),
      ),
    );

    expect(find.text('74'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
    expect(find.text('Great extension'), findsOneWidget);
    expect(find.text('Excessive trunk lean'), findsOneWidget);
    expect(find.text('Swing #1'), findsOneWidget);
  });
}
