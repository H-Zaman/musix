import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:musix/services/webm_opus_remuxer.dart';

typedef _Page = ({int flags, int granule, bool crcOk, Uint8List payload});

/// Splits an Ogg stream into pages, recomputing each page's CRC.
List<_Page> _pages(Uint8List ogg) {
  final pages = <_Page>[];
  final bd = ByteData.sublistView(ogg);
  var pos = 0;
  while (pos < ogg.length) {
    expect(ascii.decode(ogg.sublist(pos, pos + 4)), 'OggS');
    final segCount = ogg[pos + 26];
    final table = ogg.sublist(pos + 27, pos + 27 + segCount);
    final bodyLen = table.fold<int>(0, (a, b) => a + b);
    final end = pos + 27 + segCount + bodyLen;
    final stored = bd.getUint32(pos + 22, Endian.little);
    final copy = Uint8List.fromList(ogg.sublist(pos, end))
      ..fillRange(22, 26, 0);
    pages.add((
      flags: ogg[pos + 5],
      granule: bd.getInt64(pos + 6, Endian.little),
      crcOk: oggCrc(copy) == stored,
      payload: Uint8List.fromList(ogg.sublist(pos + 27 + segCount, end)),
    ));
    pos = end;
  }
  return pages;
}

void main() {
  final webm = File('test/fixtures/sine.webm').readAsBytesSync();

  test('produces a well-formed Ogg Opus stream', () {
    final pages = _pages(remuxWebmOpusToOgg(webm));

    expect(pages.length, greaterThanOrEqualTo(3));
    expect(pages.first.flags & 0x02, isNonZero, reason: 'first page is BOS');
    expect(ascii.decode(pages.first.payload.sublist(0, 8)), 'OpusHead');
    expect(ascii.decode(pages[1].payload.sublist(0, 8)), 'OpusTags');
    expect(pages.last.flags & 0x04, isNonZero, reason: 'last page is EOS');
    expect(
      pages.every((p) => p.crcOk),
      isTrue,
      reason: 'every page CRC is valid',
    );
  });

  test('final granule covers the one second of audio', () {
    final pages = _pages(remuxWebmOpusToOgg(webm));
    // 48 kHz: one second plus the encoder's pre-skip lookahead.
    expect(pages.last.granule, inInclusiveRange(48000, 48000 + 3840));
    expect(pages.last.granule % 120, 0, reason: 'whole Opus frames');
  });

  test('rejects data that is not WebM', () {
    expect(
      () => remuxWebmOpusToOgg(Uint8List.fromList([1, 2, 3, 4])),
      throwsA(isA<RemuxException>()),
    );
  });

  test('keeps the audio when the download is cut off mid-cluster', () {
    final truncated = Uint8List.sublistView(webm, 0, webm.length - 700);
    final pages = _pages(remuxWebmOpusToOgg(truncated));
    expect(pages.last.granule, greaterThan(0));
  });
}
