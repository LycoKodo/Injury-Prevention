import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tennis_form/models/coach_message.dart';
import 'package:tennis_form/services/backend_client.dart';
import 'package:tennis_form/theme/app_theme.dart';
import 'package:tennis_form/widgets/coach_card.dart';

void main() {
  testWidgets('CoachCard shows idle placeholder with no message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: CoachCard(state: CoachState())),
      ),
    );

    expect(find.text('Coach is listening'), findsOneWidget);
  });

  testWidgets('CoachCard shows problem and fix text for a sample message', (tester) async {
    const message = CoachMessage(
      swingId: 3,
      source: 'cerebras',
      items: [
        CoachItem(
          problem: 'Your elbow collapsed at contact.',
          fix: 'Drive through the ball with a firmer arm.',
        ),
      ],
      text: 'the full spoken line',
      voice: 'pending',
      generateMs: 240,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: CoachCard(state: CoachState(message: message))),
      ),
    );

    expect(find.text('Your elbow collapsed at contact.'), findsOneWidget);
    expect(find.text('Drive through the ball with a firmer arm.'), findsOneWidget);
    expect(find.textContaining('cerebras'), findsOneWidget);
    expect(find.textContaining('240ms'), findsOneWidget);
  });

  testWidgets('CoachCard shows speaking indicator while speaking', (tester) async {
    const message = CoachMessage(
      swingId: 3,
      items: [CoachItem(problem: 'p', fix: 'f')],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: CoachCard(state: CoachState(message: message, speaking: true)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Speaking…'), findsOneWidget);
  });

  testWidgets('CoachCard shows skipped-swing notice', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: CoachCard(state: CoachState(skippedSwingId: 4))),
      ),
    );

    expect(find.textContaining('Skipped swing #4'), findsOneWidget);
  });
}
