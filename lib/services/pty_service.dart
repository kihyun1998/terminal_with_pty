import 'dart:io';

import 'package:terminal_with_pty/services/pty_bidings.dart';

class PtyService {
  PtyResult? _ptyResult;
  bool _isActive = false;

  bool get isActive => _isActive;
  String? get slaveName => _ptyResult?.slaveName;
  int? get masterFd => _ptyResult?.masterFd;
  int? get slaveFd => _ptyResult?.slaveFd;

  /// PTY 생성
  Future<bool> createPty() async {
    try {
      if (_isActive) {
        print('PTY가 이미 활성화되어 있습니다.');
        return false;
      }

      final bindings = PtyBindings.instance;
      _ptyResult = bindings.openpty();

      if (_ptyResult == null) {
        print('PTY 생성 실패');
        return false;
      }

      // 마스터 파일 디스크립터를 non-blocking으로 설정
      if (!bindings.setNonBlocking(_ptyResult!.masterFd)) {
        print('Non-blocking 설정 실패');
        closePty();
        return false;
      }

      _isActive = true;
      print('PTY 생성 성공: $_ptyResult');
      return true;
    } catch (e) {
      print('PTY 생성 중 오류: $e');
      return false;
    }
  }

  /// PTY 닫기
  void closePty() {
    if (_ptyResult != null) {
      final bindings = PtyBindings.instance;

      bindings.closeFd(_ptyResult!.masterFd);
      bindings.closeFd(_ptyResult!.slaveFd);

      print('PTY 닫음: $_ptyResult');
      _ptyResult = null;
    }
    _isActive = false;
  }

  /// PTY를 위한 환경 변수 생성
  Map<String, String> createEnvironment() {
    final env = Map<String, String>.from(Platform.environment);

    if (_ptyResult?.slaveName != null) {
      env['TTY'] = _ptyResult!.slaveName!;
    }

    // Terminal.app에 필요한 환경 변수들
    env['TERM'] = 'xterm-256color';
    env['TERM_PROGRAM'] = 'Terminal';
    env['TERM_PROGRAM_VERSION'] = '2.12.7';
    env['SHELL'] = env['SHELL'] ?? '/bin/zsh';

    return env;
  }

  void dispose() {
    closePty();
  }
}
