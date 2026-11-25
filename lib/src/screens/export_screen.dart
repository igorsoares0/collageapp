import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:gal/gal.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:share_plus/share_plus.dart';

import '../api/gallery_saver.dart';
import '../model/template.dart';
import '../rendering/export.dart';
import '../theme.dart';
import '../widgets/layer_ui.dart';
import '../widgets/template_meta.dart';

/// The export, as its own place: first "developing" — each slide fades into
/// its frame as its PNG is encoded, with a count and a hairline progress —
/// then "ready": the slides to swipe through, Share (the system sheet) and
/// Save to Photos (straight to the gallery).
///
/// Takes over a [DocumentRaster] the editor captured while it was still on
/// screen (a covered route isn't painted, so the raster must come first);
/// this screen owns it from here and disposes it once the slides are cut.
class ExportScreen extends StatefulWidget {
  final DocumentRaster raster;
  final Document document;

  /// Whether the work is auto-saved as a project (the footnote says so).
  final bool projectSaved;

  const ExportScreen({
    super.key,
    required this.raster,
    required this.document,
    this.projectSaved = false,
  });

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late final int _count = widget.document.slideCount;
  final List<Uint8List> _slides = [];
  Object? _error;
  bool _saving = false;
  bool _sharing = false;

  /// Bumped after each successful save; keys the button's one-shot ✓.
  int _savedCount = 0;

  final _current = ValueNotifier<int>(0);
  final _scroll = ScrollController();

  bool get _ready => _slides.length == _count && _error == null;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_trackCurrent);
    _develop();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _current.dispose();
    super.dispose();
  }

  Future<void> _develop() async {
    try {
      await for (final png in encodeSlices(widget.raster, widget.document)) {
        if (!mounted) break;
        setState(() => _slides.add(png));
      }
      if (mounted && _slides.length == _count) HapticFeedback.lightImpact();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      // The raster is the whole document at full size (tens of MB) — gone
      // the moment the slices are cut, finished or not.
      widget.raster.dispose();
    }
  }

  double get _slideAspect =>
      widget.document.slideWidth / widget.document.slideHeight;

  void _trackCurrent() {
    const gap = 12.0;
    final w = 230 * _slideAspect + gap;
    final i = (_scroll.offset / w).round().clamp(0, _count - 1);
    if (_current.value != i) _current.value = i;
  }

  String _name(int i) =>
      _count == 1 ? widget.document.id : '${widget.document.id}_${i + 1}';

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final files = [
        for (final png in _slides) XFile.fromData(png, mimeType: 'image/png'),
      ];
      final names = [
        for (var i = 0; i < _slides.length; i++) '${_name(i)}.png',
      ];
      // fileNameOverrides is REQUIRED with XFile.fromData: cross_file drops
      // the name off-web, share_plus then invents one whose uuid-v1 slice is
      // identical across a burst, and Android flattens the temp files into
      // one cache folder by basename — every slide after the first would
      // overwrite it and the sheet would share the same PNG N times.
      await Share.shareXFiles(files, fileNameOverrides: names);
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (mounted) showLayerMessage(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Writes each slide straight into the device photo gallery, in carousel
  /// order. On Android 10+ this needs no runtime permission; older Androids
  /// and iOS get a one-time prompt via [Gal.requestAccess].
  Future<void> _saveToPhotos() async {
    setState(() => _saving = true);
    try {
      if (!await Gal.requestAccess()) {
        if (mounted) {
          showLayerMessage(
            context,
            'Allow gallery access to save your collage.',
          );
        }
        return;
      }
      // Gallery apps order photos by time, NOT filename, and default to
      // newest-first (Google Photos, the Instagram picker). Two catches:
      // Android forces DATE_ADDED to the write instant (our explicit value is
      // ignored), and when times tie it breaks by insertion order, newest row
      // first. So write the slides in REVERSE — slide 1 goes LAST, giving it
      // the highest row id, the newest DATE_ADDED, and (via GallerySaver) the
      // newest DATE_TAKEN. All three sort keys then agree and the carousel
      // reads 1→2→3, with no wall-clock spacing.
      final base = DateTime.now();
      for (var i = _slides.length - 1; i >= 0; i--) {
        await GallerySaver.save(
          _slides[i],
          name: _name(i),
          dateTaken: base.subtract(Duration(seconds: i)),
        );
      }
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _savedCount++);
    } on GalException catch (e) {
      if (mounted) showLayerMessage(context, 'Save failed: ${e.type.message}');
    } catch (e) {
      if (mounted) showLayerMessage(context, 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.document.slideWidth.round();
    final h = widget.document.slideHeight.round();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const Expanded(child: Eyebrow('Export')),
                    if (_ready || _error != null)
                      IconButton(
                        icon: const Icon(Symbols.close),
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).maybePop(),
                      )
                    else
                      Eyebrow('$w × $h · PNG', color: context.colors.inkSoft),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 280),
                  child: _error != null
                      ? _failed()
                      : _ready
                      ? _readyView()
                      : _developing(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _developing() {
    final done = _slides.length;
    return Column(
      key: const ValueKey('developing'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SerifHeadline(
          roman: 'Developing',
          italic: _count == 1 ? 'your slide.' : 'your carousel.',
          breakLine: true,
          style: AppType.headline,
        ),
        const SizedBox(height: 32),
        Flexible(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const gap = 10.0;
                final frameW = (constraints.maxWidth - 2 * gap) / 3;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (var i = 0; i < _count; i++)
                      SizedBox(
                        width: frameW,
                        height: frameW / _slideAspect,
                        child: ColoredBox(
                          color: context.colors.paperDeep,
                          child: i < done ? _Develop(png: _slides[i]) : null,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Slide '),
                  TextSpan(
                    text: twoDigits((done + 1).clamp(1, _count)),
                    style: AppType.numeral(22),
                  ),
                  TextSpan(text: ' of ${twoDigits(_count)}'),
                ],
              ),
              style: AppType.sans(15),
            ),
            const Spacer(),
            Text(
              'Rendering at full size',
              style: AppType.sans(14, color: context.colors.inkSoft),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Progress(value: _count == 0 ? 1 : done / _count),
        const Spacer(),
        Text(
          'Keep the app open — this takes a few seconds.',
          textAlign: TextAlign.center,
          style: AppType.sans(13.5, color: context.colors.inkSoft),
        ),
      ],
    );
  }

  Widget _readyView() {
    final headline = _count == 1
        ? 'One slide,'
        : '${spelledCount(_count)} slides,';
    return Column(
      key: const ValueKey('ready'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SerifHeadline(
          roman: headline,
          italic: 'ready.',
          breakLine: true,
          style: AppType.headline,
        ),
        const SizedBox(height: 32),
        SizedBox(
          height: 230,
          // Bleeds past the right margin so the next slide peeks in.
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            maxWidth: MediaQuery.sizeOf(context).width - AppSpace.margin,
            child: ListView.separated(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: AppSpace.margin),
              itemCount: _count,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => SizedBox(
                width: 230 * _slideAspect,
                child: Image.memory(
                  _slides[i],
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                _count == 1
                    ? 'Full size, ready to post'
                    : 'Swipe to check each slide',
                style: AppType.sans(14, color: context.colors.inkSoft),
              ),
            ),
            ValueListenableBuilder<int>(
              valueListenable: _current,
              builder: (context, i, _) => Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: twoDigits(i + 1),
                      style: AppType.numeral(22),
                    ),
                    TextSpan(text: ' / ${twoDigits(_count)}'),
                  ],
                ),
                style: AppType.sans(14, color: context.colors.inkSoft),
              ),
            ),
          ],
        ),
        const Spacer(),
        PrimaryButton(
          label: 'Share',
          icon: Symbols.ios_share,
          onPressed: _sharing || _saving ? null : _share,
        ),
        const SizedBox(height: 12),
        // A one-shot "Saved ✓" right after a save, then back to the label.
        // Animation-driven (no Timer), so tests can settle it.
        TweenAnimationBuilder<double>(
          key: ValueKey(_savedCount),
          tween: Tween(begin: _savedCount == 0 ? 1.0 : 0.0, end: 1.0),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 1200),
          builder: (context, t, _) => SecondaryButton(
            label: t < 1 ? 'Saved to Photos ✓' : 'Save to Photos',
            icon: t < 1 ? null : Symbols.download,
            onPressed: _sharing || _saving ? null : _saveToPhotos,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          widget.projectSaved
              ? 'Your project is saved — find it again in Projects.'
              : 'Full-size PNGs, one per slide.',
          textAlign: TextAlign.center,
          style: AppType.sans(13.5, color: context.colors.inkSoft),
        ),
      ],
    );
  }

  Widget _failed() {
    return Column(
      key: const ValueKey('failed'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SerifHeadline(
          roman: 'The export',
          italic: "didn't develop.",
          breakLine: true,
          style: AppType.headline,
        ),
        const SizedBox(height: 16),
        Text(
          'Export failed: $_error',
          style: AppType.body.copyWith(color: context.colors.inkSoft),
        ),
        const Spacer(),
        SecondaryButton(
          label: 'Back to the editor',
          icon: Symbols.arrow_back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

/// A slide developing into its frame: fades 0 → 40% → 100%.
class _Develop extends StatelessWidget {
  final Uint8List png;

  const _Develop({required this.png});

  @override
  Widget build(BuildContext context) {
    final image = Image.memory(png, fit: BoxFit.cover, gaplessPlayback: true);
    if (MediaQuery.disableAnimationsOf(context)) return image;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      builder: (context, t, child) => Opacity(
        // A quick rise to 40%, then the slow develop to full.
        opacity: t < .3 ? (t / .3) * .4 : .4 + (t - .3) / .7 * .6,
        child: child,
      ),
      child: image,
    );
  }
}

/// A 1px rule track with a 3px ink fill.
class _Progress extends StatelessWidget {
  final double value;

  const _Progress({required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 3,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 1,
            child: Hairline(color: context.colors.rule),
          ),
          AnimatedFractionallySizedBox(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 250),
            widthFactor: value.clamp(0, 1),
            child: Container(height: 3, color: context.colors.ink),
          ),
        ],
      ),
    );
  }
}
