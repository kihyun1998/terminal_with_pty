import 'dart:ffi';

import 'package:ffi/ffi.dart';

// C 함수 시그니처들
typedef OpenptyC = Int32 Function(
  Pointer<Int32> master,
  Pointer<Int32> slave,
  Pointer<Utf8> name,
  Pointer<Void> termp,
  Pointer<Void> winp,
);

typedef OpenptyDart = int Function(
  Pointer<Int32> master,
  Pointer<Int32> slave,
  Pointer<Utf8> name,
  Pointer<Void> termp,
  Pointer<Void> winp,
);

typedef CloseC = Int32 Function(Int32 fd);
typedef CloseDart = int Function(int fd);

typedef FcntlC = Int32 Function(Int32 fd, Int32 cmd, Int32 arg);
typedef FcntlDart = int Function(int fd, int cmd, int arg);

typedef TtyNameC = Pointer<Utf8> Function(Int32 fd);
typedef TtyNameDart = Pointer<Utf8> Function(int fd);

class PtyBindings {
  static PtyBindings? _instance;
  late DynamicLibrary _lib;
  late OpenptyDart _openpty;
  late CloseDart _close;
  late FcntlDart _fcntl;
  late TtyNameDart _ttyname;

  // fcntl 상수들
  static const int F_GETFL = 3;
  static const int F_SETFL = 4;
  static const int O_NONBLOCK = 0x0004;

  PtyBindings._() {
    try {
      // macOS에서 util 라이브러리 로드
      _lib = DynamicLibrary.open('/usr/lib/libutil.dylib');
    } catch (e) {
      // fallback으로 system 라이브러리 시도
      _lib = DynamicLibrary.open('/usr/lib/libSystem.dylib');
    }

    try {
      _openpty = _lib.lookupFunction<OpenptyC, OpenptyDart>('openpty');
      _close = _lib.lookupFunction<CloseC, CloseDart>('close');
      _fcntl = _lib.lookupFunction<FcntlC, FcntlDart>('fcntl');
      _ttyname = _lib.lookupFunction<TtyNameC, TtyNameDart>('ttyname');
    } catch (e) {
      throw Exception('PTY 함수 바인딩 실패: $e');
    }
  }

  static PtyBindings get instance {
    _instance ??= PtyBindings._();
    return _instance!;
  }

  /// PTY 마스터/슬레이브 쌍 생성
  PtyResult? openpty() {
    final master = calloc<Int32>();
    final slave = calloc<Int32>();

    try {
      final result = _openpty(master, slave, nullptr, nullptr, nullptr);

      if (result == -1) {
        return null;
      }

      return PtyResult(
        masterFd: master.value,
        slaveFd: slave.value,
        slaveName: _getTtyName(slave.value),
      );
    } finally {
      calloc.free(master);
      calloc.free(slave);
    }
  }

  /// 파일 디스크립터 닫기
  bool closeFd(int fd) {
    return _close(fd) == 0;
  }

  /// 파일 디스크립터를 non-blocking으로 설정
  bool setNonBlocking(int fd) {
    final flags = _fcntl(fd, F_GETFL, 0);
    if (flags == -1) return false;

    return _fcntl(fd, F_SETFL, flags | O_NONBLOCK) != -1;
  }

  /// TTY 이름 가져오기
  String? _getTtyName(int fd) {
    try {
      final namePtr = _ttyname(fd);
      if (namePtr == nullptr) return null;
      return namePtr.toDartString();
    } catch (e) {
      return null;
    }
  }
}

class PtyResult {
  final int masterFd;
  final int slaveFd;
  final String? slaveName;

  PtyResult({
    required this.masterFd,
    required this.slaveFd,
    this.slaveName,
  });

  @override
  String toString() {
    return 'PtyResult(master: $masterFd, slave: $slaveFd, name: $slaveName)';
  }
}
