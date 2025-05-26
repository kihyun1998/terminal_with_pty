import 'dart:io';

import 'package:flutter_pty/flutter_pty.dart';

class TerminalInstance {
  final String id;
  final Process? process;
  final Pty? pty;
  final DateTime startTime;
  final String launchMethod;
  bool _isRunning = true;

  TerminalInstance({
    required this.id,
    this.process,
    this.pty,
    required this.startTime,
    required this.launchMethod,
  });

  bool get isRunning {
    if (process != null) {
      // Process 상태 체크 (exitCode가 완료되었는지 확인)
      try {
        return _isRunning && (process?.pid != null);
      } catch (e) {
        return false;
      }
    }
    return _isRunning;
  }

  void markAsTerminated() {
    _isRunning = false;
  }
}

class TerminalManager {
  final Map<String, TerminalInstance> _activeTerminals = {};

  /// 새로운 터미널 실행 (여러 방법 시도)
  Future<TerminalInstance> launchTerminal() async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    // 방법 1: AppleScript 사용 (가장 안정적)
    try {
      return await _launchWithAppleScript(id);
    } catch (e) {
      print('AppleScript 방법 실패: $e');
    }

    // 방법 2: flutter_pty + open 명령어
    try {
      return await _launchWithPtyAndOpen(id);
    } catch (e) {
      print('PTY + open 방법 실패: $e');
    }

    // 방법 3: 직접 Terminal.app 실행
    try {
      return await _launchTerminalDirect(id);
    } catch (e) {
      print('직접 실행 방법 실패: $e');
    }

    throw Exception('모든 터미널 실행 방법이 실패했습니다');
  }

  /// 방법 1: AppleScript 사용
  Future<TerminalInstance> _launchWithAppleScript(String id) async {
    // PTY를 백그라운드에서 생성
    final pty = Pty.start('/bin/zsh');

    // AppleScript로 Terminal.app 실행
    final process = await Process.start(
        'osascript', ['-e', 'tell application "Terminal" to do script ""']);

    final terminal = TerminalInstance(
      id: id,
      process: process,
      pty: pty,
      startTime: DateTime.now(),
      launchMethod: 'AppleScript',
    );

    _activeTerminals[id] = terminal;

    // 프로세스 종료 감지
    process.exitCode.then((_) {
      _activeTerminals.remove(id);
      pty.kill();
    });

    return terminal;
  }

  /// 방법 2: flutter_pty + open 명령어
  Future<TerminalInstance> _launchWithPtyAndOpen(String id) async {
    // PTY 생성
    final pty = Pty.start('/bin/zsh');

    // open 명령어로 Terminal.app 실행
    final process = await Process.start('open', [
      '-a',
      'Terminal'
    ], environment: {
      ...Platform.environment,
      'TERM': 'xterm-256color',
      'SHELL': '/bin/zsh',
    });

    final terminal = TerminalInstance(
      id: id,
      process: process,
      pty: pty,
      startTime: DateTime.now(),
      launchMethod: 'PTY + open',
    );

    _activeTerminals[id] = terminal;

    // 프로세스 종료 감지
    process.exitCode.then((_) {
      _activeTerminals.remove(id);
      pty.kill();
    });

    return terminal;
  }

  /// 방법 3: 직접 Terminal.app 실행 (Process.start)
  Future<TerminalInstance> _launchTerminalDirect(String id) async {
    // PTY 환경 생성
    final pty = Pty.start('/bin/zsh');

    // 잠시 대기 (PTY 안정화)
    await Future.delayed(const Duration(milliseconds: 200));

    // Terminal.app 직접 실행
    final process = await Process.start(
      '/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal',
      [],
      environment: {
        ...Platform.environment,
        'TERM': 'xterm-256color',
        'SHELL': '/bin/zsh',
        'LANG': 'en_US.UTF-8',
        'LC_ALL': 'en_US.UTF-8',
        'COLUMNS': '80',
        'LINES': '24',
      },
      mode: ProcessStartMode.normal,
    );

    final terminal = TerminalInstance(
      id: id,
      process: process,
      pty: pty,
      startTime: DateTime.now(),
      launchMethod: 'Direct',
    );

    _activeTerminals[id] = terminal;

    // 프로세스 종료 감지
    process.exitCode.then((_) {
      _activeTerminals.remove(id);
      pty.kill();
    });

    return terminal;
  }

  /// 특정 터미널 종료
  Future<void> killTerminal(String terminalId) async {
    final terminal = _activeTerminals[terminalId];
    if (terminal != null) {
      // Process 종료
      if (terminal.process != null) {
        terminal.process!.kill(ProcessSignal.sigterm);

        // 강제 종료가 필요한 경우
        await Future.delayed(const Duration(milliseconds: 500));
        if (terminal.isRunning) {
          terminal.process!.kill(ProcessSignal.sigkill);
        }
      }

      // PTY 종료
      terminal.pty?.kill();

      // 상태 업데이트
      terminal.markAsTerminated();
      _activeTerminals.remove(terminalId);
    }
  }

  /// 모든 터미널 종료
  Future<void> killAllTerminals() async {
    final terminals = List.from(_activeTerminals.values);

    // 모든 터미널에 SIGTERM 전송
    for (final terminal in terminals) {
      if (terminal.process != null) {
        terminal.process!.kill(ProcessSignal.sigterm);
      }
      terminal.pty?.kill();
    }

    // 강제 종료 대기
    await Future.delayed(const Duration(milliseconds: 500));

    // 아직 실행 중인 터미널 강제 종료
    for (final terminal in terminals) {
      if (terminal.isRunning && terminal.process != null) {
        terminal.process!.kill(ProcessSignal.sigkill);
      }
      terminal.markAsTerminated();
    }

    _activeTerminals.clear();
  }

  /// 활성 터미널 목록 반환
  List<TerminalInstance> getActiveTerminals() {
    // 죽은 프로세스 정리
    _cleanupDeadProcesses();
    return _activeTerminals.values.toList();
  }

  /// 죽은 프로세스 정리
  void _cleanupDeadProcesses() {
    final deadTerminals = <String>[];

    for (final entry in _activeTerminals.entries) {
      if (!entry.value.isRunning) {
        deadTerminals.add(entry.key);
      }
    }

    for (final id in deadTerminals) {
      final terminal = _activeTerminals[id];
      terminal?.pty?.kill();
      _activeTerminals.remove(id);
    }
  }

  /// 특정 터미널 존재 여부 확인
  bool hasTerminal(String terminalId) {
    return _activeTerminals.containsKey(terminalId);
  }

  /// 총 터미널 개수
  int get terminalCount => _activeTerminals.length;

  /// 실행 중인 터미널 개수
  int get runningTerminalCount {
    return _activeTerminals.values.where((t) => t.isRunning).length;
  }
}
