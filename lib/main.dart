import 'package:flutter/material.dart';
import 'package:terminal_with_pty/terminal_manager.dart';

void main() {
  runApp(const TerminalLauncherApp());
}

class TerminalLauncherApp extends StatelessWidget {
  const TerminalLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'macOS Terminal Launcher',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'SF Pro Display',
      ),
      home: const TerminalLauncherHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class TerminalLauncherHome extends StatefulWidget {
  const TerminalLauncherHome({super.key});

  @override
  State<TerminalLauncherHome> createState() => _TerminalLauncherHomeState();
}

class _TerminalLauncherHomeState extends State<TerminalLauncherHome> {
  final TerminalManager _terminalManager = TerminalManager();
  List<TerminalInstance> _terminals = [];
  String _statusMessage = '준비됨';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _updateTerminalList();
  }

  @override
  void dispose() {
    _terminalManager.killAllTerminals();
    super.dispose();
  }

  void _updateTerminalList() {
    setState(() {
      _terminals = _terminalManager.getActiveTerminals();
    });
  }

  Future<void> _launchTerminal() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '터미널 실행 중...';
    });

    try {
      final terminal = await _terminalManager.launchTerminal();
      setState(() {
        _statusMessage = '터미널이 성공적으로 실행되었습니다 (ID: ${terminal.id})';
        _isLoading = false;
      });
      _updateTerminalList();

      // 터미널 종료 감지
      if (terminal.process != null) {
        terminal.process!.exitCode.then((_) {
          if (mounted) {
            setState(() {
              _statusMessage = '터미널 (ID: ${terminal.id})이 종료되었습니다';
            });
            _updateTerminalList();
          }
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = '터미널 실행 실패: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _killTerminal(String terminalId) async {
    try {
      await _terminalManager.killTerminal(terminalId);
      setState(() {
        _statusMessage = '터미널 (ID: $terminalId)을 종료했습니다';
      });
      _updateTerminalList();
    } catch (e) {
      setState(() {
        _statusMessage = '터미널 종료 실패: $e';
      });
    }
  }

  Future<void> _killAllTerminals() async {
    try {
      await _terminalManager.killAllTerminals();
      setState(() {
        _statusMessage = '모든 터미널을 종료했습니다';
      });
      _updateTerminalList();
    } catch (e) {
      setState(() {
        _statusMessage = '터미널 종료 실패: $e';
      });
    }
  }

  Widget _buildTerminalCard(TerminalInstance terminal) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: Icon(
          Icons.terminal,
          color: terminal.isRunning ? Colors.green : Colors.grey,
        ),
        title: Text('터미널 ${terminal.id}'),
        subtitle: Text(
          'PID: ${terminal.process?.pid ?? 'N/A'} | '
          '실행 시간: ${terminal.startTime.hour}:${terminal.startTime.minute.toString().padLeft(2, '0')} | '
          '상태: ${terminal.isRunning ? '실행중' : '종료됨'}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.info_outline, color: Colors.blue),
              onPressed: () => _showTerminalInfo(terminal),
              tooltip: '터미널 정보',
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              onPressed:
                  terminal.isRunning ? () => _killTerminal(terminal.id) : null,
              tooltip: '터미널 종료',
            ),
          ],
        ),
      ),
    );
  }

  void _showTerminalInfo(TerminalInstance terminal) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('터미널 ${terminal.id} 정보'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${terminal.id}'),
            Text('PID: ${terminal.process?.pid ?? 'N/A'}'),
            Text('실행 시간: ${terminal.startTime}'),
            Text('런처 방식: ${terminal.launchMethod}'),
            Text('상태: ${terminal.isRunning ? '실행 중' : '종료됨'}'),
            Text('PTY 활성: ${terminal.pty != null ? 'Yes' : 'No'}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('macOS Terminal Launcher'),
        backgroundColor: Colors.blueGrey[800],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 상태 표시 영역
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.blueGrey[50],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _isLoading
                          ? Icons.hourglass_empty
                          : (_terminals.isNotEmpty
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked),
                      color: _isLoading
                          ? Colors.orange
                          : (_terminals.isNotEmpty
                              ? Colors.green
                              : Colors.grey),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '활성 터미널: ${_terminals.where((t) => t.isRunning).length}개 / 총 ${_terminals.length}개',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.blueGrey[600],
                  ),
                ),
              ],
            ),
          ),

          // 버튼 영역
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _launchTerminal,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.launch),
                    label: Text(_isLoading ? '실행 중...' : '새 터미널 열기'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _terminals.where((t) => t.isRunning).isEmpty
                      ? null
                      : _killAllTerminals,
                  icon: const Icon(Icons.clear_all),
                  label: const Text('모두 종료'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                  ),
                ),
              ],
            ),
          ),

          // 터미널 목록
          Expanded(
            child: _terminals.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.terminal,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '실행 중인 터미널이 없습니다',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '"새 터미널 열기" 버튼을 눌러서 시작하세요',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _terminals.length,
                    itemBuilder: (context, index) {
                      return _buildTerminalCard(_terminals[index]);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading ? null : _launchTerminal,
        tooltip: '새 터미널 열기',
        backgroundColor: Colors.green,
        child: const Icon(Icons.add),
      ),
    );
  }
}
