import 'dart:async';

import 'package:diff_view/src/model/diff_line.dart';
import 'package:diff_view/src/model/line_coords.dart';

/// Where the painter gets rows. Implementations page lines in from a
/// backend or hold them in memory (tests, small files).
///
/// [lineAt] must be cheap: the painter calls it for every visible row on
/// every frame. A line that is not loaded yet returns null, and the painter
/// paints a placeholder and asks for it with [prefetch]. When requested
/// lines arrive, or loaded lines change (syntax tokens that arrive after
/// the rows, rows fetched again after a reload), the source notifies its
/// listeners and returns the new [DiffLine] objects from [lineAt]; the
/// painter's layout cache rebuilds a row whose line no longer lays out the
/// same ([DiffLine.sameLayoutAs]).
abstract interface class DiffLineSource {
  /// The line, or null while it is not loaded.
  DiffLine? lineAt(PaneSide side, int line);

  /// Asks for [span] on [side] (the visible rows plus a margin). Must not
  /// notify listeners synchronously: the painter calls it while painting.
  void prefetch(PaneSide side, ModelSpan span);

  /// Loads [span] on [side] if needed and returns its lines in order (copy
  /// of rows that are not on screen).
  Future<List<DiffLine>> load(PaneSide side, ModelSpan span);

  /// Registers [listener], called when lines arrive or change.
  void addListener(void Function() listener);

  /// Removes a listener added with [addListener].
  void removeListener(void Function() listener);
}

/// A [DiffLineSource] over lines already in memory.
final class MemoryLineSource implements DiffLineSource {
  /// Creates a source over the lines of each side, indexed by model line.
  new({required List<DiffLine> old, required List<DiffLine> neu})
    : _sides = [old, neu];

  final List<List<DiffLine>> _sides;

  @override
  DiffLine? lineAt(PaneSide side, int line) {
    final lines = _sides[side.index];
    return line >= 0 && line < lines.length ? lines[line] : null;
  }

  @override
  void prefetch(PaneSide side, ModelSpan span) {}

  @override
  Future<List<DiffLine>> load(PaneSide side, ModelSpan span) =>
      Future.value(_sides[side.index].sublist(span.start, span.end));

  @override
  void addListener(void Function() listener) {}

  @override
  void removeListener(void Function() listener) {}
}
