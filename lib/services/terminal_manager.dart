import 'dart:async';
import 'dart:io';

import 'pty_service.dart';

class TerminalInfo {
  final int pid;
  final DateTime startTime;
  final PtyService ptyService;
  final Process process;

  TerminalInfo({
    required this.pid,
    required this.startTime,
    required this.ptyService,
    required this.process,
  });
}

class TerminalManager {
  static const String terminalPath =
      '/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal';

  final Map<int, TerminalInfo> _activeTerminals = {};
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  Stream<String> get logStream => _logController.stream;
  List<TerminalInfo> get activeTerminals => _activeTerminals.values.toList();
  int get activeCount => _activeTerminals.length;

  /// Terminal.app을 PTY와 함께 시작
  Future<bool> startTerminal() async {
    try {
      _log('터미널 시작 시도...');

      // 1. PTY 생성
      final ptyService = PtyService();
      if (!await ptyService.createPty()) {
        _log('PTY 생성 실패');
        return false;
      }

      _log('PTY 생성 성공: ${ptyService.slaveName}');

      // 2. 환경 변수 준비
      final environment = ptyService.createEnvironment();
      _log('환경 변수 설정 완료');

      // 3. Terminal.app 실행
      final process = await Process.start(
        terminalPath,
        [],
        environment: environment,
        mode: ProcessStartMode.detached,
        runInShell: false,
      );

      final terminalInfo = TerminalInfo(
        pid: process.pid,
        startTime: DateTime.now(),
        ptyService: ptyService,
        process: process,
      );

      _activeTerminals[process.pid] = terminalInfo;
      _log('터미널 시작 성공 (PID: ${process.pid})');

      // 4. 프로세스 종료 감지
      process.exitCode.then((exitCode) {
        _handleTerminalExit(process.pid, exitCode);
      });

      return true;
    } catch (e) {
      _log('터미널 시작 실패: $e');
      return false;
    }
  }

  /// 특정 터미널 종료
  Future<bool> killTerminal(int pid) async {
    final terminalInfo = _activeTerminals[pid];
    if (terminalInfo == null) {
      _log('PID $pid 터미널을 찾을 수 없음');
      return false;
    }

    try {
      terminalInfo.process.kill(ProcessSignal.sigterm);
      _log('터미널 종료 신호 전송 (PID: $pid)');
      return true;
    } catch (e) {
      _log('터미널 종료 실패 (PID: $pid): $e');
      return false;
    }
  }

  /// 모든 터미널 종료
  Future<void> killAllTerminals() async {
    final pids = _activeTerminals.keys.toList();
    _log('모든 터미널 종료 시작 (${pids.length}개)');

    for (final pid in pids) {
      await killTerminal(pid);
    }
  }

  /// 터미널 종료 처리
  void _handleTerminalExit(int pid, int exitCode) {
    final terminalInfo = _activeTerminals.remove(pid);
    if (terminalInfo != null) {
      terminalInfo.ptyService.dispose();
      _log('터미널 종료됨 (PID: $pid, 종료코드: $exitCode)');
    }
  }

  /// 터미널 정보 가져오기
  TerminalInfo? getTerminalInfo(int pid) {
    return _activeTerminals[pid];
  }

  /// 로그 기록
  void _log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logMessage = '[$timestamp] $message';
    print(logMessage);
    _logController.add(logMessage);
  }

  /// 정리
  void dispose() {
    killAllTerminals();
    _logController.close();
  }
}
