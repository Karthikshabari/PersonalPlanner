/// Validates a directed relationship graph without mutating it.
///
/// The visited set makes malformed or cyclic history data bounded even when a
/// remote payload points at a long or otherwise unexpected chain.
void validateAcyclicLinks(Map<String, Set<String>> graph) {
  // A three-state traversal shares completed suffixes between roots, so a
  // whole history graph is checked in O(V + E) rather than once per chain.
  final colors = <String, _VisitColor>{};
  for (final start in graph.keys) {
    if (colors[start] == _VisitColor.complete) continue;
    final stack = <(String, bool)>[(start, false)];
    while (stack.isNotEmpty) {
      final (node, exiting) = stack.removeLast();
      if (exiting) {
        colors[node] = _VisitColor.complete;
        continue;
      }
      final color = colors[node];
      if (color == _VisitColor.active) {
        throw StateError('History links must be acyclic');
      }
      if (color == _VisitColor.complete) continue;

      final next = graph[node];
      if (next != null && next.length > 1) {
        throw StateError('History links must have one successor');
      }
      colors[node] = _VisitColor.active;
      stack.add((node, true));
      if (next != null && next.isNotEmpty) {
        stack.add((next.single, false));
      }
    }
  }
}

enum _VisitColor { active, complete }
