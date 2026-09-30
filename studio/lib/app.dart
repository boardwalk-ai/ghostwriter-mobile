import 'package:cockpit_ui/cockpit_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:study_studio/study_studio.dart';

/// Study Studio as its own app: mounts only the Study Studio module's routes.
///
/// The module still links to `/` for the Cockpit launcher (bottom nav "Home" /
/// "Cockpit"); with no launcher here, `/` redirects to the studio root.
final routerProvider = Provider<GoRouter>((ref) {
  const module = StudyStudioModule();
  return GoRouter(
    initialLocation: module.rootPath,
    routes: [
      GoRoute(path: '/', redirect: (_, _) => module.rootPath),
      ...module.routes(),
    ],
  );
});

class StudyStudioApp extends ConsumerWidget {
  const StudyStudioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeControllerProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Study Studio',
      debugShowCheckedModeBanner: false,
      theme: themeState.light,
      darkTheme: themeState.dark,
      themeMode: themeState.mode,
      routerConfig: router,
    );
  }
}
