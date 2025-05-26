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

  /// Terminal.app을 PTY와 함께 시작 (방법 1: script 명령어 사용)
  Future<bool> startTerminal() async {
    return await _startTerminalWithScript();
  }

  /// script 명령어를 사용한 터미널 시작
  Future<bool> _startTerminalWithScript() async {
    try {
      _log('터미널 시작 시도 (script 명령어 사용)...');

      // script 명령어로 pseudo-tty 환경에서 터미널 실행
      final process = await Process.start(
        'script',
        [
          '-q', // quiet 모드
          '/dev/null', // 출력을 /dev/null로 버림
          terminalPath,
        ],
        mode: ProcessStartMode.detached,
      );

      final terminalInfo = TerminalInfo(
        pid: process.pid,
        startTime: DateTime.now(),
        ptyService: PtyService(), // 빈 서비스
        process: process,
      );

      _activeTerminals[process.pid] = terminalInfo;
      _log('터미널 시작 성공 (PID: ${process.pid})');

      // 프로세스 종료 감지
      process.exitCode.then((exitCode) {
        _handleTerminalExit(process.pid, exitCode);
      });

      return true;
    } catch (e) {
      _log('터미널 시작 실패: $e');
      return false;
    }
  }

  /// PTY를 직접 생성하는 방법 (대안) - public 메서드
  Future<bool> startTerminalWithDirectPty() async {
    return await _startTerminalWithDirectPty();
  }

  /// PTY를 직접 생성하는 방법 (대안)
  Future<bool> _startTerminalWithDirectPty() async {
    PtyService? ptyService;

    try {
      _log('터미널 시작 시도 (직접 PTY 생성)...');

      // 1. PTY 생성
      ptyService = PtyService();
      if (!await ptyService.createPty()) {
        _log('PTY 생성 실패');
        return false;
      }

      _log('PTY 생성 성공: ${ptyService.slaveName}');

      // 2. 환경 변수 준비
      final environment = _createEnhancedEnvironment(ptyService);
      _log('환경 변수 설정 완료');

      // 3. Terminal.app 실행
      final process = await Process.start(
        terminalPath,
        [],
        environment: environment,
        mode: ProcessStartMode.detached,
        runInShell: false,
      );

      _log('터미널 프로세스 생성됨 (PID: ${process.pid})');

      // 4. 터미널 정보 저장
      final terminalInfo = TerminalInfo(
        pid: process.pid,
        startTime: DateTime.now(),
        ptyService: ptyService,
        process: process,
      );

      _activeTerminals[process.pid] = terminalInfo;

      // 5. 잠시 기다린 후 터미널이 실제로 실행되었는지 확인
      await Future.delayed(Duration(milliseconds: 500));

      final isRunning = await _checkProcessRunning(process.pid);
      if (isRunning) {
        _log('터미널 실행 확인 완료 (PID: ${process.pid})');

        // detached 프로세스 추적 (안전하게)
        _safelyTrackProcess(process);

        return true;
      } else {
        _log('터미널 프로세스가 즉시 종료됨');
        _activeTerminals.remove(process.pid);
        ptyService.dispose();
        return false;
      }
    } catch (e) {
      _log('터미널 시작 중 오류: $e');
      ptyService?.dispose();
      return false;
    }
  }

  /// 프로세스가 실행 중인지 확인
  Future<bool> _checkProcessRunning(int pid) async {
    try {
      final result = await Process.run('kill', ['-0', pid.toString()]);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// detached 프로세스를 안전하게 추적
  void _safelyTrackProcess(Process process) {
    // 5초마다 프로세스 상태 확인
    Timer.periodic(Duration(seconds: 5), (timer) async {
      if (!_activeTerminals.containsKey(process.pid)) {
        timer.cancel();
        return;
      }

      final isRunning = await _checkProcessRunning(process.pid);
      if (!isRunning) {
        _log('터미널 프로세스 종료 감지 (PID: ${process.pid})');
        _handleTerminalExit(process.pid, 0);
        timer.cancel();
      }
    });
  }

  /// 향상된 환경 변수 생성
  Map<String, String> _createEnhancedEnvironment(PtyService ptyService) {
    final env = Map<String, String>.from(Platform.environment);

    // PTY 관련 설정
    if (ptyService.slaveName != null) {
      env['TTY'] = ptyService.slaveName!;
    }

    // Terminal.app에 필요한 환경 변수들
    env['TERM'] = 'xterm-256color';
    env['TERM_PROGRAM'] = 'Terminal';
    env['TERM_PROGRAM_VERSION'] = '2.12.7';
    env['SHELL'] = env['SHELL'] ?? '/bin/zsh';

    // 추가 환경 변수들
    env['COLORTERM'] = 'truecolor';
    env['LANG'] = env['LANG'] ?? 'en_US.UTF-8';
    env['LC_ALL'] = env['LC_ALL'] ?? 'en_US.UTF-8';

    // macOS 특화 설정
    env['__CF_USER_TEXT_ENCODING'] = '0x1F5:0x0:0x0';
    env['TMPDIR'] = env['TMPDIR'] ?? '/tmp';

    return env;
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
