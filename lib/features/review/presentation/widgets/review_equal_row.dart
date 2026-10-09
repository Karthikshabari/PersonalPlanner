import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A row of children with equal widths and equal heights (the tallest child
/// sets the height). Unlike `IntrinsicHeight`, it lays children out with real
/// constraints, so children may contain a `LayoutBuilder`.
class ReviewEqualRow extends MultiChildRenderObjectWidget {
  const ReviewEqualRow({super.key, required this.spacing, super.children});

  final double spacing;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEqualRow(spacing);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderEqualRow).spacing = spacing;
  }
}

class _EqualRowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderEqualRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _EqualRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _EqualRowParentData> {
  _RenderEqualRow(this._spacing);

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
    final cell = math.max(0.0, (width - _spacing * (count - 1)) / count);
    var tallest = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      c.layout(
        BoxConstraints(minWidth: cell, maxWidth: cell),
        parentUsesSize: true,
      );
      tallest = math.max(tallest, c.size.height);
    }
    var x = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
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
    final cell = math.max(
      0.0,
      (constraints.maxWidth - _spacing * (count - 1)) / count,
    );
    var tallest = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
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
