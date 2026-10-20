import 'dart:convert';
import 'dart:typed_data';

/// Thrown when the input is not a WebM file with a single Opus audio track.
class RemuxException implements Exception {
  final String message;
  RemuxException(this.message);
  @override
  String toString() => 'RemuxException: $message';
}

/// Lossless WebM(Opus) -> Ogg Opus.
///
/// YouTube serves its best audio as WebM/Opus, but flutter_soloud only
/// decodes Ogg-contained Opus. The Opus packets are identical in both
/// containers, so this just re-wraps them: no decoding, no native code.
Uint8List remuxWebmOpusToOgg(Uint8List webm, {int serial = 0x4d555358}) {
  final track = _parseWebm(webm);
  return _OggWriter(serial).write(track.opusHead, track.packets);
}

class _WebmTrack {
  final Uint8List opusHead;
  final List<Uint8List> packets;
  _WebmTrack(this.opusHead, this.packets);
}

// EBML element ids we care about (ids keep their length-marker bits).
const _idSegment = 0x18538067;
const _idTracks = 0x1654AE6B;
const _idTrackEntry = 0xAE;
const _idTrackNumber = 0xD7;
const _idCodecId = 0x86;
const _idCodecPrivate = 0x63A2;
const _idCluster = 0x1F43B675;
const _idSimpleBlock = 0xA3;
const _idBlockGroup = 0xA0;
const _idBlock = 0xA1;

const _containers = {
  _idSegment,
  _idTracks,
  _idTrackEntry,
  _idCluster,
  _idBlockGroup,
};

int _vintLength(int first) {
  if (first == 0) throw RemuxException('invalid EBML vint');
  var len = 1;
  var mask = 0x80;
  while (first & mask == 0) {
    len++;
    mask >>= 1;
  }
  return len;
}

class _Reader {
  final Uint8List data;
  int pos;
  _Reader(this.data, this.pos);

  int readId() {
    final len = _vintLength(data[pos]);
    if (len > 4) throw RemuxException('bad EBML id at $pos');
    var id = 0;
    for (var i = 0; i < len; i++) {
      id = (id << 8) | data[pos + i];
    }
    pos += len;
    return id;
  }

  /// Returns the size, or -1 for "unknown size".
  int readSize() {
    final first = data[pos];
    final len = _vintLength(first);
    final valueMask = (1 << (8 - len)) - 1;
    var value = first & valueMask;
    var allOnes = value == valueMask;
    for (var i = 1; i < len; i++) {
      final b = data[pos + i];
      if (b != 0xFF) allOnes = false;
      value = (value << 8) | b;
    }
    pos += len;
    return allOnes ? -1 : value;
  }
}

_WebmTrack _parseWebm(Uint8List data) {
  Uint8List? opusHead;
  int? opusTrackNumber;
  final packets = <Uint8List>[];

  // Per-TrackEntry scratch.
  String? codecId;
  Uint8List? codecPrivate;
  var trackNumber = 0;

  void walk(int start, int end, int parentId) {
    final r = _Reader(data, start);
    while (r.pos < end) {
      final id = r.readId();
      var size = r.readSize();
      final bodyStart = r.pos;
      if (size < 0) size = end - bodyStart; // unknown size: runs to parent end
      final bodyEnd = bodyStart + size;
      if (bodyEnd > end) {
        // Truncated tail (e.g. interrupted download): keep what we have.
        if (_containers.contains(id)) walk(bodyStart, end, id);
        return;
      }

      if (_containers.contains(id)) {
        if (id == _idTrackEntry) {
          codecId = null;
          codecPrivate = null;
          trackNumber = 0;
        }
        walk(bodyStart, bodyEnd, id);
        if (id == _idTrackEntry && codecId == 'A_OPUS' && opusHead == null) {
          opusHead = codecPrivate;
          opusTrackNumber = trackNumber;
        }
      } else if (parentId == _idTrackEntry) {
        if (id == _idCodecId) {
          codecId = utf8.decode(data.sublist(bodyStart, bodyEnd));
        } else if (id == _idCodecPrivate) {
          codecPrivate = Uint8List.sublistView(data, bodyStart, bodyEnd);
        } else if (id == _idTrackNumber) {
          trackNumber = 0;
          for (var i = bodyStart; i < bodyEnd; i++) {
            trackNumber = (trackNumber << 8) | data[i];
          }
        }
      } else if (id == _idSimpleBlock || id == _idBlock) {
        final packet = _blockPayload(data, bodyStart, bodyEnd, opusTrackNumber);
        if (packet != null) packets.add(packet);
      }
      r.pos = bodyEnd;
    }
  }

  walk(0, data.length, 0);

  final head = opusHead;
  if (head == null || head.length < 19) {
    throw RemuxException('no Opus track found');
  }
  if (packets.isEmpty) throw RemuxException('no audio packets found');
  return _WebmTrack(head, packets);
}

Uint8List? _blockPayload(Uint8List data, int start, int end, int? wantedTrack) {
  final trackLen = _vintLength(data[start]);
  var track = data[start] & ((1 << (8 - trackLen)) - 1);
  for (var i = 1; i < trackLen; i++) {
    track = (track << 8) | data[start + i];
  }
  var pos = start + trackLen + 2; // skip the relative timecode
  final flags = data[pos++];
  if (wantedTrack != null && track != wantedTrack) return null;
  if (flags & 0x06 != 0) throw RemuxException('laced blocks are not supported');
  return Uint8List.sublistView(data, pos, end);
}

/// Samples (at 48 kHz) an Opus packet decodes to, from its TOC byte.
int _packetSamples(Uint8List packet) {
  if (packet.isEmpty) return 0;
  final toc = packet[0];
  final config = toc >> 3;
  final int frameSamples;
  if (config < 12) {
    frameSamples = const [480, 960, 1920, 2880][config % 4];
  } else if (config < 16) {
    frameSamples = const [480, 960][config % 2];
  } else {
    frameSamples = const [120, 240, 480, 960][config % 4];
  }
  final frames = switch (toc & 0x03) {
    0 => 1,
    1 || 2 => 2,
    _ => packet.length > 1 ? packet[1] & 0x3F : 1,
  };
  return frames * frameSamples;
}

class _OggWriter {
  final int serial;
  final _out = BytesBuilder(copy: false);
  var _seq = 0;
  _OggWriter(this.serial);

  Uint8List write(Uint8List opusHead, List<Uint8List> packets) {
    _page(flags: 0x02, granule: 0, packets: [opusHead]);

    final tags = BytesBuilder()
      ..add(ascii.encode('OpusTags'))
      ..add(_le32(6))
      ..add(ascii.encode('musix1'))
      ..add(_le32(0));
    _page(flags: 0, granule: 0, packets: [tags.toBytes()]);

    var granule = 0;
    var pending = <Uint8List>[];
    var segments = 0;
    for (final p in packets) {
      final needed = p.length ~/ 255 + 1;
      if (segments + needed > 255 && pending.isNotEmpty) {
        _page(flags: 0, granule: granule, packets: pending);
        pending = [];
        segments = 0;
      }
      pending.add(p);
      segments += needed;
      granule += _packetSamples(p);
    }
    _page(flags: 0x04, granule: granule, packets: pending);
    return _out.toBytes();
  }

  void _page({
    required int flags,
    required int granule,
    required List<Uint8List> packets,
  }) {
    final table = <int>[];
    for (final p in packets) {
      var n = p.length;
      while (n >= 255) {
        table.add(255);
        n -= 255;
      }
      table.add(n);
    }
    final page = BytesBuilder()
      ..add(ascii.encode('OggS'))
      ..addByte(0)
      ..addByte(flags)
      ..add(_le64(granule))
      ..add(_le32(serial))
      ..add(_le32(_seq++))
      ..add(_le32(0)) // crc placeholder, filled in below
      ..addByte(table.length)
      ..add(table);
    for (final p in packets) {
      page.add(p);
    }
    final bytes = page.toBytes();
    bytes.setRange(22, 26, _le32(oggCrc(bytes)));
    _out.add(bytes);
  }

  static Uint8List _le32(int v) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
  static Uint8List _le64(int v) =>
      Uint8List(8)..buffer.asByteData().setInt64(0, v, Endian.little);
}

final List<int> _crcTable = List.generate(256, (i) {
  var r = i << 24;
  for (var j = 0; j < 8; j++) {
    r = (r & 0x80000000) != 0 ? ((r << 1) ^ 0x04C11DB7) : (r << 1);
    r &= 0xFFFFFFFF;
  }
  return r;
});

/// Ogg's CRC-32 (poly 0x04C11DB7, no reflection, no final xor).
int oggCrc(Uint8List bytes) {
  var crc = 0;
  for (final b in bytes) {
    crc = ((crc << 8) & 0xFFFFFFFF) ^ _crcTable[((crc >> 24) & 0xFF) ^ b];
  }
  return crc;
}
