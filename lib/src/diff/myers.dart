import 'dart:typed_data';

/// One step of an edit script from `a` to `b`.
enum EditOp {
  /// The element is in both.
  equal,

  /// The element of `a` is removed.
  delete,

  /// The element of `b` is added.
  insert,
}

/// The shortest edit script from [a] to [b] (Myers' O((N+M)D) algorithm).
///
/// Memory grows with the number of differences D times the length, so a
/// pair of large, completely different inputs is expensive.
List<EditOp> myersDiff(List<int> a, List<int> b) {
  var prefix = 0;
  while (prefix < a.length && prefix < b.length && a[prefix] == b[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < a.length - prefix &&
      suffix < b.length - prefix &&
      a[a.length - 1 - suffix] == b[b.length - 1 - suffix]) {
    suffix++;
  }
  final x0 = prefix;
  final n = a.length - prefix - suffix;
  final m = b.length - prefix - suffix;
  return [
    for (var i = 0; i < prefix; i++) EditOp.equal,
    ..._middle(a, b, x0, n, m),
    for (var i = 0; i < suffix; i++) EditOp.equal,
  ];
}

List<EditOp> _middle(List<int> a, List<int> b, int at, int n, int m) {
  if (n == 0) return List.filled(m, EditOp.insert);
  if (m == 0) return List.filled(n, EditOp.delete);
  final max = n + m;
  final offset = max + 1;
  final v = Int32List(2 * max + 3);
  final trace = <Int32List>[];
  for (var d = 0; d <= max; d++) {
    trace.add(Int32List.fromList(v));
    for (var k = -d; k <= d; k += 2) {
      var x = k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])
          ? v[offset + k + 1]
          : v[offset + k - 1] + 1;
      var y = x - k;
      while (x < n && y < m && a[at + x] == b[at + y]) {
        x++;
        y++;
      }
      v[offset + k] = x;
      if (x >= n && y >= m) return _backtrack(trace, offset, n, m);
    }
  }
  throw StateError('unreachable');
}

List<EditOp> _backtrack(List<Int32List> trace, int offset, int n, int m) {
  final ops = <EditOp>[];
  var x = n;
  var y = m;
  for (var d = trace.length - 1; d >= 0; d--) {
    final v = trace[d];
    final k = x - y;
    final prevK = k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])
        ? k + 1
        : k - 1;
    final prevX = v[offset + prevK];
    final prevY = prevX - prevK;
    while (x > prevX && y > prevY) {
      ops.add(EditOp.equal);
      x--;
      y--;
    }
    if (d > 0) ops.add(x == prevX ? EditOp.insert : EditOp.delete);
    x = prevX;
    y = prevY;
  }
  return ops.reversed.toList();
}
