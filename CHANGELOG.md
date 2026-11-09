## 0.2.0

- `UnifiedDiff`: a single-column view driven by the same `DiffViewController`, with old and new line numbers, deleted then inserted lines per change, folds, inlays, gutter selection with copy and syntax colours.
- `UnifiedRows` maps unified rows to old and new lines; `RowSelection` and `RowSelectionController` hold the unified selection.
- `jumpToLine`, `viewportYOfLine` and `ensureLineVisible` act on the unified view when it is the one laid out. Switching views keeps the line in place.
- `GutterMetrics.unified` and `DiffPaintResources.unifiedGutter` lay out the two-number gutter; `DiffPaneViewport` takes `unified`.
- The example app has a Split/Unified switch.

## 0.1.0

- First release: `SideBySideDiff`, `DiffViewController`, `TextDiff` and the paging `DiffLineSource`.
