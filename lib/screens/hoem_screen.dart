import 'dart:async';

import 'package:flutter/material.dart';

import '../services/terminal_manager.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TerminalManager _terminalManager = TerminalManager();
  final List<String> _logs = [];
  late StreamSubscription<String> _logSubscription;
  bool _isStarting = false;

  @override
  void initState() {
    super.initState();
    _logSubscription = _terminalManager.logStream.listen((log) {
      setState(() {
        _logs.add(log);
        if (_logs.length > 100) {
          _logs.removeAt(0); // 로그 100줄로 제한
        }
      });
    });
  }

  @override
  void dispose() {
    _logSubscription.cancel();
    _terminalManager.dispose();
    super.dispose();
  }

  Future<void> _startTerminal() async {
    if (_isStarting) return;

    setState(() {
      _isStarting = true;
    });

    final success = await _terminalManager.startTerminal();

    setState(() {
      _isStarting = false;
    });

    if (!success) {
      _showSnackBar('터미널 시작 실패', isError: true);
    } else {
      _showSnackBar('터미널 시작 성공');
    }
  }

  Future<void> _killTerminal(int pid) async {
    final success = await _terminalManager.killTerminal(pid);
    _showSnackBar(
      success ? '터미널 종료 신호 전송' : '터미널 종료 실패',
      isError: !success,
    );
  }

  Future<void> _killAllTerminals() async {
    await _terminalManager.killAllTerminals();
    _showSnackBar('모든 터미널 종료 신호 전송');
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminal Manager'),
        backgroundColor: Colors.blueGrey[800],
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 컨트롤 패널
            _buildControlPanel(),
            const SizedBox(height: 20),

            // 활성 터미널 목록
            _buildActiveTerminals(),
            const SizedBox(height: 20),

            // 로그
            _buildLogPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '터미널 제어',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _isStarting ? null : _startTerminal,
                  icon: _isStarting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_isStarting ? '시작 중...' : '터미널 시작'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _terminalManager.activeCount > 0
                      ? _killAllTerminals
                      : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('모든 터미널 종료'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTerminals() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '활성 터미널',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_terminalManager.activeCount}개',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_terminalManager.activeCount == 0)
              const Text('활성 터미널이 없습니다.')
            else
              ...(_terminalManager.activeTerminals.map((terminal) {
                final duration = DateTime.now().difference(terminal.startTime);
                final formattedDuration =
                    '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.terminal, color: Colors.green[600]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PID: ${terminal.pid}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'PTY: ${terminal.ptyService.slaveName ?? "N/A"}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                            Text(
                              '실행 시간: $formattedDuration',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _killTerminal(terminal.pid),
                        icon: const Icon(Icons.close, color: Colors.red),
                        tooltip: '터미널 종료',
                      ),
                    ],
                  ),
                );
              })),
          ],
        ),
      ),
    );
  }

  Widget _buildLogPanel() {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '로그',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _clearLogs,
                    icon: const Icon(Icons.clear),
                    tooltip: '로그 지우기',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: _logs.isEmpty
                      ? const Text('로그가 없습니다.')
                      : ListView.builder(
                          itemCount: _logs.length,
                          itemBuilder: (context, index) {
                            return Text(
                              _logs[index],
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
