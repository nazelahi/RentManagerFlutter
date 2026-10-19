import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/models/models.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:rentmanager/features/work_orders/work_orders_view.dart';

void main() {
  Directory? tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rentmanager_wo_test');
    await AppStorage.initWithPath(tempDir!.path);
  });

  tearDownAll(() async {
    try {
      await tempDir?.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('Edit Work Order page opens and renders without unbounded height exception',
      (tester) async {
    final sampleOrder = WorkOrder(
      id: 'wo_123',
      title: 'Fix kitchen sink leak',
      description: 'Water leaking under the pipe',
      status: 'pending',
      category: 'Plumbing',
      assignedTo: 'John Plumber',
      createdAt: '2026-10-15T10:00:00.000Z',
      dueDate: '2026-10-20T10:00:00.000Z',
      workerCost: 150.0,
      productPrice: 45.0,
      unit: 'Unit 101',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => WorkOrdersView.showEditModal(context, sampleOrder),
                  child: const Text('Open Edit'),
                ),
              );
            },
          ),
        ),
      ),
    );

    // Tap to open Edit Work Order modal
    await tester.tap(find.text('Open Edit'));
    await tester.pumpAndSettle();

    // Verify Edit Work Order header and fields rendered without crash
    expect(find.text('Edit Work Order'), findsOneWidget);
    expect(find.text('Fix kitchen sink leak'), findsOneWidget);
    expect(find.text('Water leaking under the pipe'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);

    // Ensure no layout exceptions were thrown
    expect(tester.takeException(), isNull);
  });
}
