import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frameon/main.dart';

void main() {
  testWidgets('FrameonApp launches without error', (WidgetTester tester) async {
    await tester.pumpWidget(const FrameonApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}