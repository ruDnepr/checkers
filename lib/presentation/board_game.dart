import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_riverpod/flame_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/game_controller.dart';
import '../domain/models.dart';

/// The same controller is read by Flutter controls and the Flame component.
final activeGameProvider = Provider<GameController>(
  (ref) => throw StateError('Нет активной партии'),
);

class DianaBoardGame extends FlameGame with RiverpodGameMixin {
  DianaBoardGame({required this.flipped});
  final bool flipped;
  @override
  Color backgroundColor() => Colors.transparent;
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await camera.viewport.add(_BoardComponent(flipped: flipped));
  }
}

class _BoardComponent extends PositionComponent with RiverpodComponentMixin {
  _BoardComponent({required this.flipped});
  final bool flipped;
  GameController? controller;
  MoveAnimation? _lastAnimation;
  double _elapsed = 0;
  double _time = 0;

  @override
  void onMount() {
    addToGameWidgetBuild(() {
      controller = ref.watch(activeGameProvider);
    });
    super.onMount();
  }

  @override
  void onGameResize(Vector2 canvasSize) {
    super.onGameResize(canvasSize);
    size = canvasSize;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    final next = controller?.animation;
    if (!identical(next, _lastAnimation)) {
      _lastAnimation = next;
      _elapsed = 0;
    }
    _elapsed += dt;
  }

  Offset _center(Square square, int n, double cell) {
    final row = flipped ? n - 1 - square.row : square.row;
    final col = flipped ? n - 1 - square.col : square.col;
    return Offset((col + .5) * cell, (row + .5) * cell);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final game = controller;
    if (game == null || size.x <= 0) return;
    final n = game.state.board.size;
    final cell = size.x / n;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final rect = Rect.fromLTWH(c * cell, r * cell, cell, cell);
        final dark = (r + c).isOdd;
        final colors = dark
            ? [const Color(0xFF8C5A2C), const Color(0xFF69401F)]
            : [const Color(0xFFFFD65E), const Color(0xFFEFB94A)];
        canvas.drawRect(
          rect,
          Paint()
            ..shader = ui.Gradient.linear(
              rect.topLeft,
              rect.bottomRight,
              colors,
            ),
        );
        canvas.drawRect(
          rect.deflate(.4),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .55
            ..color = Colors.white.withValues(alpha: dark ? .05 : .12),
        );
      }
    }

    if (game.settings.hints) {
      if (game.selected != null) {
        final selectedLocation = game.selectedPath.isEmpty
            ? game.selected!
            : game.selectedPath.last;
        _ring(
          canvas,
          _center(selectedLocation, n, cell),
          cell * .44,
          const Color(0xFFFFF5B7),
          3,
        );
        for (final destination in game.suggestedDestinations) {
          final center = _center(destination, n, cell);
          canvas.drawCircle(
            center,
            cell * .23,
            Paint()..color = const Color(0xAAFFF5BF),
          );
          canvas.drawCircle(
            center,
            cell * .11,
            Paint()..color = const Color(0xFFFCF6CE),
          );
        }
      }
      final hint = game.suggestedMove;
      if (hint != null) {
        final pulse = 1.0 + .035 * math.sin(_time * 5);
        _ring(
          canvas,
          _center(hint.from, n, cell),
          cell * .44 * pulse,
          const Color(0xFFFFEF9A),
          3.5,
        );
        final dest = _center(hint.landings.first, n, cell);
        canvas.drawCircle(
          dest,
          cell * .25 * pulse,
          Paint()..color = const Color(0xCCFFF2A3),
        );
        canvas.drawCircle(
          dest,
          cell * .12,
          Paint()..color = const Color(0xFFFFFCDF),
        );
      }
    }

    final animation = game.animation;
    if (animation != null) {
      final path = [animation.move.from, ...animation.move.landings];
      final total = math.max(.001, animation.duration.inMicroseconds / 1000000);
      final progress = (_elapsed / total * animation.move.landings.length)
          .clamp(0.0, animation.move.landings.length.toDouble());
      final segment = progress.floor().clamp(
        0,
        animation.move.landings.length - 1,
      );
      final t = (progress - segment).clamp(0.0, 1.0);
      final eased = Curves.easeInOut.transform(t);
      final from = _center(path[segment], n, cell);
      final to = _center(path[segment + 1], n, cell);
      for (final entry in animation.before.board.pieces.entries) {
        if (entry.key == animation.move.from) continue;
        final captureIndex = animation.move.captures.indexOf(entry.key);
        if (captureIndex >= 0 && captureIndex < segment) continue;
        final opacity = captureIndex == segment
            ? (1 - (t * 1.5).clamp(0.0, 1.0))
            : 1.0;
        _piece(
          canvas,
          _center(entry.key, n, cell),
          cell,
          entry.value,
          opacity: opacity,
        );
      }
      var moving = animation.before.board.at(animation.move.from)!;
      if (!moving.king &&
          (game.state.variant == GameVariant.russian ||
              game.state.variant == GameVariant.giveaway) &&
          path
              .take(segment + 1)
              .any((p) => p.row == (moving.side == Side.white ? 0 : n - 1))) {
        moving = moving.crown();
      }
      final point =
          Offset.lerp(from, to, eased)! +
          Offset(0, -math.sin(math.pi * eased) * cell * .10);
      _piece(canvas, point, cell, moving);
      return;
    }

    final preview = game.selectedPath.isNotEmpty
        ? game.selectedCandidates.firstOrNull
        : null;
    for (final entry in game.state.board.pieces.entries) {
      if (preview != null &&
          (entry.key == preview.from ||
              preview.captures
                  .take(game.selectedPath.length)
                  .contains(entry.key))) {
        continue;
      }
      _piece(canvas, _center(entry.key, n, cell), cell, entry.value);
    }
    if (preview != null) {
      var moving = game.state.board.at(preview.from)!;
      if (!moving.king &&
          (game.state.variant == GameVariant.russian ||
              game.state.variant == GameVariant.giveaway) &&
          game.selectedPath.any(
            (p) => p.row == (moving.side == Side.white ? 0 : n - 1),
          )) {
        moving = moving.crown();
      }
      _piece(canvas, _center(game.selectedPath.last, n, cell), cell, moving);
    }
  }

  void _ring(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double width,
  ) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  void _piece(
    Canvas canvas,
    Offset center,
    double cell,
    Piece piece, {
    double opacity = 1,
  }) {
    if (opacity <= 0) return;
    final radius = cell * .37;
    final dark = piece.side == Side.black;
    canvas.saveLayer(
      Rect.fromCircle(center: center, radius: cell * .65),
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(0, cell * .18),
        width: radius * 2.05,
        height: radius * .8,
      ),
      Paint()
        ..color = const Color(0x660F0807)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      center + Offset(0, cell * .065),
      radius,
      Paint()..color = dark ? const Color(0xFF1F1D26) : const Color(0xFFBCA985),
    );
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          center + Offset(-radius * .35, -radius * .45),
          radius * 1.55,
          dark
              ? const [Color(0xFF777781), Color(0xFF41414C), Color(0xFF24232D)]
              : const [Color(0xFFFFFEF7), Color(0xFFFFF2D9), Color(0xFFCFBE9C)],
          const [0, .55, 1],
        ),
    );
    canvas.drawCircle(
      center,
      radius * .74,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, cell * .035)
        ..color = piece.king
            ? const Color(0xFFFFDB6C)
            : (dark ? const Color(0xFF73717A) : const Color(0xFFD5C3A0)),
    );
    canvas.drawArc(
      rect.deflate(radius * .18),
      math.pi * 1.12,
      math.pi * .62,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.0, cell * .025)
        ..color = Colors.white.withValues(alpha: dark ? .3 : .72),
    );
    if (piece.king) {
      final star = Path();
      for (var i = 0; i < 10; i++) {
        final angle = -math.pi / 2 + i * math.pi / 5;
        final r = radius * (i.isEven ? .42 : .20);
        final p = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
        if (i == 0) {
          star.moveTo(p.dx, p.dy);
        } else {
          star.lineTo(p.dx, p.dy);
        }
      }
      star.close();
      canvas.drawPath(star, Paint()..color = const Color(0xFFF4C755));
    }
    canvas.restore();
  }
}

class BoardView extends StatefulWidget {
  const BoardView({super.key, required this.controller, required this.flipped});
  final GameController controller;
  final bool flipped;
  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> {
  late final DianaBoardGame game = DianaBoardGame(flipped: widget.flipped);
  final gameKey = GlobalKey<RiverpodAwareGameWidgetState<DianaBoardGame>>();
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: Semantics(
      label:
          'Игровая доска ${widget.controller.state.board.size} на ${widget.controller.state.board.size}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final box = context.findRenderObject() as RenderBox;
          final cell = box.size.width / widget.controller.state.board.size;
          var col = (details.localPosition.dx / cell).floor();
          var row = (details.localPosition.dy / cell).floor();
          final n = widget.controller.state.board.size;
          if (row < 0 || col < 0 || row >= n || col >= n) return;
          if (widget.flipped) {
            row = n - 1 - row;
            col = n - 1 - col;
          }
          widget.controller.tap(Square(row, col));
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: RiverpodAwareGameWidget<DianaBoardGame>(
            key: gameKey,
            game: game,
          ),
        ),
      ),
    ),
  );
}
