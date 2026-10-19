/// A side-by-side diff view of one file, like JetBrains IDEs': self-painted
/// rows with cached paragraphs, curved ribbons between two
/// synced panes, word and syntax highlights, nested folds, inline inlays
/// with scroll anchoring, and gutter line selection with copy.
///
/// Self-contained: it depends on Flutter only. Rows come from a
/// [DiffLineSource] the host implements (paged from a backend, or in
/// memory: [MemoryLineSource]). [TextDiff] computes a diff of two texts.
library;

import 'package:side_by_side_diff/side_by_side_diff.dart' show DiffLineSource, MemoryLineSource, TextDiff;

export 'src/diff/myers.dart' show EditOp, myersDiff;
export 'src/diff/text_diff.dart';
export 'src/model/diff_document.dart';
export 'src/model/diff_line.dart';
export 'src/model/fold_model.dart';
export 'src/model/height_index.dart';
export 'src/model/inlays.dart';
export 'src/model/line_coords.dart';
export 'src/model/line_source.dart';
export 'src/model/pane_geometry.dart';
export 'src/model/selection.dart';
export 'src/model/sync_map.dart';
export 'src/render/diff_theme.dart';
export 'src/render/line_layout.dart';
export 'src/render/paint_resources.dart';
export 'src/render/render_diff_pane.dart';
export 'src/render/ribbon_painter.dart';
export 'src/widgets/diff_pane.dart';
export 'src/widgets/diff_view_controller.dart';
export 'src/widgets/side_by_side_diff.dart';
