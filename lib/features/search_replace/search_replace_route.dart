import 'package:go_router/go_router.dart';

import 'presentation/views/search_replace_view.dart';

abstract final class SearchReplaceRoute {
  static const name = 'search-replace';
  static const path = 'search-replace';

  static GoRoute get route => GoRoute(
    name: name,
    path: path,
    builder: (_, _) => const SearchReplaceView(),
  );
}
