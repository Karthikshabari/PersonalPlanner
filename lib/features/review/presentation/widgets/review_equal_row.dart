import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A row of children with equal widths and equal heights (the tallest child
/// sets the height). Unlike `IntrinsicHeight`, it lays children out with real
/// constraints, so children may contain a `LayoutBuilder`.
///
/// [flexes] (one per child) splits the width in those proportions instead of
/// equally; null, or a list of the wrong length, keeps equal widths.
class ReviewEqualRow extends MultiChildRenderObjectWidget {
  const ReviewEqualRow({
    super.key,
    required this.spacing,
    this.flexes,
    super.children,
  });

  final double spacing;
  final List<int>? flexes;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEqualRow(spacing, flexes);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderEqualRow)
      ..spacing = spacing
      ..flexes = flexes;
  }
}

class _EqualRowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderEqualRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _EqualRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _EqualRowParentData> {
  _RenderEqualRow(this._spacing, this._flexes);

  List<int>? _flexes;
  set flexes(List<int>? value) {
    if (listEquals(value, _flexes)) return;
    _flexes = value;
    markNeedsLayout();
  }

  /// Width of the child at [index] among [count] children in [width].
  double _cell(double width, int count, int index) {
    final room = math.max(0.0, width - _spacing * (count - 1));
    final flexes = _flexes;
    if (flexes == null || flexes.length != count) return room / count;
    final total = flexes.fold<int>(0, (a, b) => a + b);
    return total <= 0 ? room / count : room * flexes[index] / total;
  }

  double _spacing;
  double get spacing => _spacing;
  set spacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _EqualRowParentData) {
      child.parentData = _EqualRowParentData();
    }
  }

  int get _count {
    var count = 0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      count++;
    }
    return count;
  }

  @override
  void performLayout() {
    final count = _count;
    if (count == 0) {
      size = constraints.constrain(Size.zero);
      return;
    }
    final width = constraints.maxWidth;
    var tallest = 0.0;
    var index = 0;
    for (var c = firstChild; c != null; c = childAfter(c), index++) {
      final cell = _cell(width, count, index);
      c.layout(
        BoxConstraints(minWidth: cell, maxWidth: cell),
        parentUsesSize: true,
      );
      tallest = math.max(tallest, c.size.height);
    }
    var x = 0.0;
    index = 0;
    for (var c = firstChild; c != null; c = childAfter(c), index++) {
      final cell = _cell(width, count, index);
      if (c.size.height < tallest) {
        c.layout(
          // A minimum, not a tight height: a tight child is a relayout
          // boundary, so its own growth (e.g. an editor opening) would never
          // reach this row and would overflow instead of resizing it.
          BoxConstraints(minWidth: cell, maxWidth: cell, minHeight: tallest),
          parentUsesSize: true,
        );
      }
      (c.parentData! as _EqualRowParentData).offset = Offset(x, 0);
      x += cell + _spacing;
    }
    size = constraints.constrain(Size(width, tallest));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final count = _count;
    if (count == 0) return constraints.constrain(Size.zero);
    var tallest = 0.0;
    var index = 0;
    for (var c = firstChild; c != null; c = childAfter(c), index++) {
      final cell = _cell(constraints.maxWidth, count, index);
      tallest = math.max(
        tallest,
        c.getDryLayout(BoxConstraints.tightFor(width: cell)).height,
      );
    }
    return constraints.constrain(Size(constraints.maxWidth, tallest));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
