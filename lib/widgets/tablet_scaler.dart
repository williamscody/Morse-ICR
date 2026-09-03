import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Renders every screen against the same phone-sized canvas they were
/// actually designed for, then visually blows the whole result up to
/// fill a tablet's extra screen space, rather than leaving the fixed
/// phone-width layout floating small in a sea of blank space (morse_icr
/// project: iPad/Android-tablet support, 2026-09-02).
///
/// Wire this in as [MaterialApp.builder] so it wraps every route
/// (including dialogs/snackbars, which live in the same Navigator
/// subtree) -- no per-screen layout code needs its own idea of what a
/// tablet is. Below [_tabletShortestSide] it's a no-op, so phone
/// behavior is untouched.
class TabletScaler extends StatelessWidget {
  const TabletScaler({super.key, required this.child});

  final Widget child;

  /// Material's own phone/tablet breakpoint (shortest side, logical px).
  static const double _tabletShortestSide = 600;

  /// A standard modern-phone portrait canvas -- roughly iPhone-class
  /// logical points -- since that's the canvas every screen in this app
  /// was actually laid out against.
  static const double _referenceWidth = 390;
  static const double _referenceHeight = 844;

  static const double _minScale = 1.0;
  static const double _maxScale = 2.0;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    if (size.shortestSide < _tabletShortestSide) return child;

    // The smaller of the two axis ratios is the binding one -- using it
    // (rather than, say, width alone) guarantees the synthetic canvas
    // descendants lay out against is never *shorter* than a real phone
    // in either dimension, whatever a given tablet's aspect ratio, so
    // nothing ends up more visually cramped than it already is on a
    // phone. Clamped so a tiny "tablet" (right at the breakpoint) never
    // shrinks below 1x and a huge one never blows up past 2x.
    final scale = math
        .min(size.width / _referenceWidth, size.height / _referenceHeight)
        .clamp(_minScale, _maxScale);
    if (scale == _minScale) return child;

    final scaledSize = size / scale;
    return MediaQuery(
      data: mediaQuery.copyWith(
        size: scaledSize,
        padding: mediaQuery.padding / scale,
        viewPadding: mediaQuery.viewPadding / scale,
        viewInsets: mediaQuery.viewInsets / scale,
      ),
      // FittedBox, not Transform.scale -- Transform is paint-only and
      // leaves the child's actual layout box alone, so when the ambient
      // constraints coming down from above happen to be tight (confirmed
      // on-device: a live Android rotation without Activity recreation
      // hits this, though a fresh portrait launch reproduced it too),
      // the inner SizedBox's requested size is clamped straight back up
      // to the full physical size by BoxConstraints.enforce -- Transform
      // then scales that already-full-size content up *again*, blowing
      // it out past the right/bottom edge (confirmed via an Android
      // tablet-emulator screenshot, both iPad and Android landscape were
      // fine, only Android portrait clipped). FittedBox's render object
      // always gives its child loose/unconstrained layout first, so the
      // SizedBox reliably gets its real requested size no matter what
      // the ambient constraints are, then scales the result to fill --
      // the same visual effect as Transform.scale, without depending on
      // the parent happening to hand down loose constraints.
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: scaledSize.width,
          height: scaledSize.height,
          child: child,
        ),
      ),
    );
  }
}
