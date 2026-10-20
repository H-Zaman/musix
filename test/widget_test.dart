import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musix/screens/musix_player_screen.dart';

void main() {
  testWidgets('equalizer subscribes once across parent rebuilds', (tester) async {
    var listens = 0;
    final controller = StreamController<Float32List>.broadcast(
      onListen: () => listens++,
    );
    addTearDown(controller.close);

    Widget app(bool playing) => MaterialApp(
          home: SizedBox(
            width: 200,
            height: 60,
            child: WinampEqualizer(
              isPlaying: playing,
              fftStream: controller.stream,
            ),
          ),
        );

    await tester.pumpWidget(app(false));
    await tester.pumpWidget(app(true));
    await tester.pumpWidget(app(false));

    expect(listens, 1);
  });

  testWidgets('equalizer repaints on an FFT frame without throwing', (tester) async {
    final controller = StreamController<Float32List>.broadcast();
    addTearDown(controller.close);

    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 200,
        height: 60,
        child: WinampEqualizer(isPlaying: true, fftStream: controller.stream),
      ),
    ));

    controller.add(Float32List.fromList(List.filled(256, 0.5)));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
