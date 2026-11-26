## 0.4.0

- `DiffThemeData.minTextContrast` keeps code readable on line and word tints. A run on a tint keeps the WCAG contrast its colour has on the plain background, up to this floor: if it reads less on its tint, only its lightness changes, hue and saturation kept, by the least change that gets there (away from the tint first, then the other way), and never to a colour that reads worse. The one case where the hue isn't kept: when no change of lightness gets there, white or black is used if it reads better. It works on sRGB colours. Text on the plain background, the gutter, the line-selection band, fold labels and the text selection are left alone. 0, the default, turns it off and draws everything as before. On, a recoloured line keeps one more paragraph per view, counted against the line cache, and takes about twice as long to lay out the first time it shows.
- `DiffViewController.maxCachedLines` (and `ParagraphCache.maxEntries`) count paragraphs: one per line, plus the recoloured ones. With the contrast off that is the number of lines, as before.
- `ParagraphCache.paragraphs` gives the paragraphs held, the recoloured ones included.

## 0.3.0

- Text selection in the code: drag to select by character across lines, in one pane or across the unified rows as shown, with autoscroll past the edges. Double click selects a word, triple click a line, Shift-click extends the selection or selects from the last click, a click elsewhere or Escape clears. The pointer is a text cursor over code.
- Cmd/Ctrl+C copies the selected text as shown: lines joined by their own line ends, no markers or line numbers, folded lines left out. Lines a paging source hasn't loaded are loaded first.
- `DiffViewController.textSelection` (a `CodeSelectionController`, a `ValueListenable<CodeSelection?>`), `clearTextSelection` and `textOf`; `CodeSelection` and `CodePosition` give the side, start and end as line and column. `selectionChanges` fires for it. `textSelectionEnabled` (on by default) turns it off.
- One selection at a time: a text selection clears the gutter selection and the other way round. `copySelection` copies whichever there is, the unified one included.
- `DiffThemeData.textSelection`, set in both built-in themes; unset, the selection colour is used. The built-in colours are opaque, so a changed word's tint does not show inside a selection; a colour with transparency keeps it.
- `LineLayout.offsetAt` hit tests a laid-out line.
- `DiffPaneViewport` takes `textSelection`.
- The example app shows the selection and has a Copy button.

## 0.2.0

- `UnifiedDiff`: a single-column view driven by the same `DiffViewController`, with old and new line numbers, deleted then inserted lines per change, folds, inlays, gutter selection with copy and syntax colours.
- `UnifiedRows` maps unified rows to old and new lines; `RowSelection` and `RowSelectionController` hold the unified selection.
- `jumpToLine`, `viewportYOfLine` and `ensureLineVisible` act on the unified view when it is the one laid out. Switching views keeps the line in place.
- `GutterMetrics.unified` and `DiffPaintResources.unifiedGutter` lay out the two-number gutter; `DiffPaneViewport` takes `unified`.
- `DiffThemeData.unifiedDeletedLine` and `unifiedDeletedWord` tint removed lines in the unified view; unset, they're the side-by-side colours.
- The example app has a Split/Unified switch.
- `selectionChanges` and `geometryChanges` also fire for the unified view.
- `DiffPane` is a `StatelessWidget`.
- Fix: an inlay added to a file shorter than the viewport no longer scrolls the view past its end and springs back.

## 0.1.0

- First release: `SideBySideDiff`, `DiffViewController`, `TextDiff` and the paging `DiffLineSource`.
