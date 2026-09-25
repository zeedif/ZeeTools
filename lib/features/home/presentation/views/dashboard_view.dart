import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '/features/search_replace/search_replace_route.dart';

class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: GridView.count(
        crossAxisCount: 3,
        padding: const EdgeInsets.all(16),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        children: [
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => context.goNamed(SearchReplaceRoute.name),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.find_replace_rounded, size: 36),
                  SizedBox(height: 8),
                  Text('Búsqueda y Reemplazo'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
