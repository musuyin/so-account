import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BotanicalArt {
  const BotanicalArt(this.large, this.small);
  final ui.Image large, small;
}

final botanicalArtProvider = FutureProvider<BotanicalArt>((ref) async {
  Future<ui.Image> load(String path, int width) async {
    final bytes = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(),
      targetWidth: width,
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  final large = await load('assets/themes/cucumber-large.png', 1200);
  final small = await load('assets/themes/cucumber-small.png', 900);
  // Keep images alive for outgoing animated themes until the app closes.
  return BotanicalArt(large, small);
});

void _paintArt(Canvas canvas, Rect rect, ui.Image image, double opacity) {
  paintImage(
    canvas: canvas,
    rect: rect,
    image: image,
    fit: BoxFit.cover,
    alignment: Alignment.centerRight,
    opacity: opacity,
    filterQuality: FilterQuality.medium,
  );
}

class BotanicalCardBorder extends RoundedRectangleBorder {
  const BotanicalCardBorder({
    required this.image,
    required this.opacity,
    super.borderRadius = const BorderRadius.all(Radius.circular(24)),
    super.side,
  });
  final ui.Image image;
  final double opacity;

  @override
  BotanicalCardBorder copyWith({
    BorderSide? side,
    BorderRadiusGeometry? borderRadius,
  }) => BotanicalCardBorder(
    image: image,
    opacity: opacity,
    side: side ?? this.side,
    borderRadius: borderRadius ?? this.borderRadius,
  );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is RoundedRectangleBorder) {
      return BotanicalCardBorder(
        image: image,
        opacity: ui.lerpDouble(
          a is BotanicalCardBorder ? a.opacity : 0,
          opacity,
          t,
        )!,
        side: BorderSide.lerp(a.side, side, t),
        borderRadius: BorderRadiusGeometry.lerp(
          a.borderRadius,
          borderRadius,
          t,
        )!,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is RoundedRectangleBorder) {
      return BotanicalCardBorder(
        image: image,
        opacity: ui.lerpDouble(
          opacity,
          b is BotanicalCardBorder ? b.opacity : 0,
          t,
        )!,
        side: BorderSide.lerp(side, b.side, t),
        borderRadius: BorderRadiusGeometry.lerp(
          borderRadius,
          b.borderRadius,
          t,
        )!,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  bool operator ==(Object other) =>
      other is BotanicalCardBorder &&
      other.image == image &&
      other.opacity == opacity &&
      other.side == side &&
      other.borderRadius == borderRadius;
  @override
  int get hashCode => Object.hash(image, opacity, side, borderRadius);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final path = getOuterPath(rect, textDirection: textDirection);
    canvas.save();
    canvas.clipPath(path);
    _paintArt(canvas, rect, image, opacity);
    canvas.restore();
    super.paint(canvas, rect, textDirection: textDirection);
  }
}

class BotanicalInputBorder extends OutlineInputBorder {
  const BotanicalInputBorder({
    required this.image,
    required this.opacity,
    super.borderSide = BorderSide.none,
    super.borderRadius = const BorderRadius.all(Radius.circular(16)),
    super.gapPadding,
  });
  final ui.Image image;
  final double opacity;

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is OutlineInputBorder) {
      return BotanicalInputBorder(
        image: image,
        opacity: ui.lerpDouble(
          a is BotanicalInputBorder ? a.opacity : 0,
          opacity,
          t,
        )!,
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
        gapPadding: ui.lerpDouble(a.gapPadding, gapPadding, t)!,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is OutlineInputBorder) {
      return BotanicalInputBorder(
        image: image,
        opacity: ui.lerpDouble(
          opacity,
          b is BotanicalInputBorder ? b.opacity : 0,
          t,
        )!,
        borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
        borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
        gapPadding: ui.lerpDouble(gapPadding, b.gapPadding, t)!,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  bool operator ==(Object other) =>
      other is BotanicalInputBorder &&
      other.image == image &&
      other.opacity == opacity &&
      other.borderSide == borderSide &&
      other.borderRadius == borderRadius &&
      other.gapPadding == gapPadding;
  @override
  int get hashCode =>
      Object.hash(image, opacity, borderSide, borderRadius, gapPadding);

  @override
  BotanicalInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
  }) => BotanicalInputBorder(
    image: image,
    opacity: opacity,
    borderSide: borderSide ?? this.borderSide,
    borderRadius: borderRadius ?? this.borderRadius,
    gapPadding: gapPadding ?? this.gapPadding,
  );

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0,
    double gapPercentage = 0,
    TextDirection? textDirection,
  }) {
    canvas.save();
    canvas.clipRRect(borderRadius.toRRect(rect));
    _paintArt(canvas, rect, image, opacity);
    canvas.restore();
    super.paint(
      canvas,
      rect,
      gapStart: gapStart,
      gapExtent: gapExtent,
      gapPercentage: gapPercentage,
      textDirection: textDirection,
    );
  }
}
