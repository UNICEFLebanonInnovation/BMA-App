import 'package:flutter/material.dart';

import '../layout/app_layout.dart';

/// The BMA lockup, as the website draws it.
///
/// The asset is cropped from BMA-NFE's own `clm_plus_logo.png` — the file its
/// login page serves — by `tool/make_icons.py`. It is shown **as drawn**: its
/// blue is #1975BB, which is not this app's navy #003366, and it is not
/// recoloured to match. A brand mark is not a palette swatch, and a logo that
/// differs between the website and the app is worse than one that differs
/// from the button next to it.
class BmaLogo extends StatelessWidget {
  const BmaLogo({super.key, this.width, this.markOnly = false});

  /// Width in logical pixels. Defaults to a size that suits the measured box:
  /// the lockup carries a line of type, so it needs more room on a tablet to
  /// stay legible and less on a phone to leave room for the form.
  final double? width;

  /// The monogram without the tagline, for somewhere too small to read it.
  final bool markOnly;

  /// Aspect ratios of the two assets, so the box is reserved before the image
  /// decodes and the form below it never jumps.
  static const double _lockupAspect = 680 / 270;
  static const double _markAspect = 603 / 215;

  @override
  Widget build(BuildContext context) {
    final layout = LayoutScope.of(context);
    final resolved = width ?? (layout.width.atLeastMedium ? 260.0 : 200.0);
    final aspect = markOnly ? _markAspect : _lockupAspect;
    return Semantics(
      label: 'BMA',
      image: true,
      child: ExcludeSemantics(
        // Centred, because the sign-in and setup cards lay their children out
        // with CrossAxisAlignment.stretch: without this the lockup is widened
        // to the card and the fixed width below is silently ignored.
        child: Center(
          heightFactor: 1,
          child: SizedBox(
            width: resolved,
            height: resolved / aspect,
            child: Image.asset(
              markOnly ? 'assets/images/bma_mark.png' : 'assets/images/bma_logo.png',
              fit: BoxFit.contain,
              // The logo is the one thing on the sign-in screen that tells the
              // worker they opened the right app, so it must not scale away
              // with the text — hence a fixed box rather than a text-scaled one.
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }
}
