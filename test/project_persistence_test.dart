import 'dart:io';

import 'package:collageapp/src/api/project_store.dart';
import 'package:collageapp/src/model/template.dart';
import 'package:collageapp/src/screens/template_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextStyle testFontResolver(String family, TextStyle base) => base;

void main() {
  late Directory dir;
  late ProjectStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('project_persistence_test');
    store = ProjectStore(dirOverride: dir);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<void> pumpDraft(WidgetTester tester) async {
    tester.view.physicalSize = const Size(540, 960);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: TemplateScreen(
          draft: Template.blank(),
          projects: store,
          fontResolver: testFontResolver,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Taps a bottom-toolbar button by its label (Text, Layout, Panel, ...).
  Future<void> addFromToolbar(WidgetTester tester, String item) async {
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  /// Whether some saved project.json on disk contains [needle]. Synchronous
  /// on purpose — safe to call from the fake-async test zone.
  bool savedContains(String needle) {
    final root = Directory('${dir.path}/projects');
    if (!root.existsSync()) return false;
    try {
      return root
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('project.json'))
          .any((f) => f.readAsStringSync().contains(needle));
    } on FileSystemException {
      // Caught the store mid-swap (Windows renames aren't atomic here);
      // the next drain iteration re-checks.
      return false;
    }
  }

  /// Drains the store's write queue from inside a widget test. The queue's
  /// future chain hops zones: its continuations were registered in the test's
  /// fake-async zone (they only run on pump), while the file IO completes on
  /// the real event loop (it only runs inside runAsync). Awaiting the queue
  /// in either zone alone deadlocks — so alternate a fake-zone microtask
  /// flush with a slice of real event loop until [done] reports the bytes
  /// have landed.
  Future<void> drainWrites(WidgetTester tester, {bool Function()? done}) async {
    for (var i = 0; i < (done == null ? 10 : 200); i++) {
      if (done != null && done()) return;
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    if (done != null) {
      expect(done(), isTrue, reason: 'the write never reached the disk');
    }
  }

  testWidgets('editing auto-saves a project that resumes with its content', (
    tester,
  ) async {
    await pumpDraft(tester);
    await addFromToolbar(tester, 'Panel');
    expect(find.byKey(const ValueKey('slide-background-1')), findsOneWidget);

    // The debounced save fires without any further interaction (typing-style
    // edits produce no canvas pointer-up to piggyback on). The added slide
    // shows up as slideCount 2 — the continuous document has no panel ids.
    await tester.pump(const Duration(seconds: 3));
    await drainWrites(tester, done: () => savedContains('"slideCount":2'));

    final list = await tester.runAsync(() => store.list());
    expect(list, hasLength(1));
    expect(list!.single.name, 'New collage');
    final project = await tester.runAsync(
      () => store.loadAsDocument(list.single.id),
    );
    // The editor authors v4 now, so the saved document carries the second
    // slide in its own structure instead of as a SlotContent override.
    expect(project!.document.slideCount, 2);

    // Resuming the saved project restores the second panel.
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: TemplateScreen(
          project: project,
          projects: store,
          fontResolver: testFontResolver,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('slide-background-1')), findsOneWidget);
    // Let the disposed first screen's queued cleanup finish before tearDown
    // deletes the directory under it.
    await drainWrites(tester);
  });

  testWidgets('further edits update the SAME project instead of forking', (
    tester,
  ) async {
    await pumpDraft(tester);
    await addFromToolbar(tester, 'Panel');
    await tester.pump(const Duration(seconds: 3));
    await drainWrites(tester, done: () => savedContains('"slideCount":2'));

    await addFromToolbar(tester, 'Panel');
    await tester.pump(const Duration(seconds: 3));
    await drainWrites(tester, done: () => savedContains('"slideCount":3'));

    final list = await tester.runAsync(() => store.list());
    expect(list, hasLength(1));
    final project = await tester.runAsync(
      () => store.loadAsDocument(list!.single.id),
    );
    // Three slides in ONE project — the edits updated it instead of forking.
    expect(project!.document.slideCount, 3);
  });

  testWidgets('browsing without editing never creates a project', (
    tester,
  ) async {
    await pumpDraft(tester);
    // Select nothing, edit nothing, leave.
    await tester.pumpWidget(const SizedBox());
    await drainWrites(tester);
    expect(await tester.runAsync(() => store.list()), isEmpty);
  });
}
