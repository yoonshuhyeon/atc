import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'dart:convert';

void main() {
  runApp(const AtcApp());
}

class AtcApp extends StatelessWidget {
  const AtcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ATC',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const RoomJoinPage(),
    );
  }
}

class RoomJoinPage extends StatefulWidget {
  const RoomJoinPage({super.key});

  @override
  State<RoomJoinPage> createState() => _RoomJoinPageState();
}

class _RoomJoinPageState extends State<RoomJoinPage> {
  final _serverController = TextEditingController(text: '127.0.0.1:8000');
  final _roomCodeController = TextEditingController();
  final _nicknameController = TextEditingController();
  String _selectedGender = 'M'; // 기본값 남성

  WebSocketChannel? _channel;
  String? _status;
  String? _roomCode;
  String? _myId;
  int? _silenceSeconds;
  List<dynamic> _participants = [];
  String? _prompt;
  double? _silentFor;
  String? _selectedTargetId;

  bool get _isConnected => _channel != null;

  @override
  void dispose() {
    _disconnect();
    _serverController.dispose();
    _roomCodeController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  void _connect() {
    final server = _serverController.text.trim();
    final roomCode = _roomCodeController.text.trim().toUpperCase();
    final nickname = _nicknameController.text.trim();

    if (server.isEmpty || roomCode.isEmpty || nickname.isEmpty) {
      setState(() {
        _status = '서버, 룸코드, 닉네임을 모두 입력하세요.';
      });
      return;
    }

    _disconnect();

    final uri = Uri.parse('ws://$server/ws/$roomCode');
    final channel = WebSocketChannel.connect(uri);

    setState(() {
      _channel = channel;
      _status = '연결 중…';
      _roomCode = roomCode;
      _participants = [];
      _silenceSeconds = null;
      _prompt = null;
      _silentFor = null;
      _myId = null;
      _selectedTargetId = null;
    });

    channel.stream.listen(
      (event) {
        _handleServerEvent(event);
      },
      onError: (error) {
        setState(() {
          _status = '연결 에러: $error';
        });
        _disconnect();
      },
      onDone: () {
        setState(() {
          _status = '연결 종료';
        });
        _disconnect();
      },
    );

    // 접속 직후 닉네임과 성별 정보를 포함한 join 이벤트 전송
    _send({'type': 'join', 'gender': _selectedGender, 'nickname': nickname});
  }

  void _disconnect() {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      channel.sink.close();
    }
  }

  void _send(Map<String, Object?> message) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode(message));
  }

  void _handleServerEvent(dynamic event) {
    try {
      final decoded = jsonDecode(event as String);
      if (decoded is! Map) return;

      final type = decoded['type'];
      if (type == 'state') {
        setState(() {
          _status = '연결됨';
          _roomCode = (decoded['room_code'] as String?) ?? _roomCode;
          _myId = decoded['my_id'] as String?;
          _silenceSeconds = decoded['silence_seconds'] as int?;
          _participants = (decoded['participants'] as List<dynamic>?) ?? [];
        });
        return;
      }

      if (type == 'presence') {
        setState(() {
          _participants = (decoded['participants'] as List<dynamic>?) ?? [];
        });
        return;
      }

      if (type == 'prompt') {
        setState(() {
          _prompt = decoded['prompt'] as String?;
          final silentForValue = decoded['silent_for'];
          _silentFor = silentForValue is num ? silentForValue.toDouble() : null;
        });
        return;
      }

      if (type == 'pick_confirmed') {
        setState(() {
          _selectedTargetId = decoded['target_id'] as String?;
        });
        return;
      }

      if (type == 'pick_reset') {
        setState(() {
          _selectedTargetId = null;
        });
        return;
      }

      if (type == 'final_result') {
        final message = decoded['message'] as String;
        
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('매칭 결과 발표'),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('확인')),
            ],
          ),
        );
        return;
      }

      if (type == 'error') {
        setState(() {
          _status = '서버 에러: ${decoded['message']}';
        });
        return;
      }
    } catch (e) {
      debugPrint('이벤트 처리 에러: $e');
    }
  }

  void _sendActivity() {
    _send({'type': 'activity'});
  }

  void _pickParticipant(String id) {
    _send({'type': 'pick', 'target_id': id});
  }

  @override
  Widget build(BuildContext context) {
    final myInfo = _participants.any((p) => p['id'] == _myId) ? _participants.firstWhere((p) => p['id'] == _myId) : null;
    final myTeam = myInfo?['team'];
    // 이성 팀원만 필터링
    final potentialMatches = _participants.where((p) => p['team'] != myTeam).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ATC - 술자리 내비게이터'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _isConnected ? _sendActivity : null,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!_isConnected) ...[
                TextField(
                  controller: _serverController,
                  decoration: const InputDecoration(labelText: 'Server (host:port)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _roomCodeController,
                  decoration: const InputDecoration(labelText: 'Room code', border: OutlineInputBorder()),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nicknameController,
                  decoration: const InputDecoration(labelText: '나의 닉네임', border: OutlineInputBorder(), hintText: '예: 강남차은우'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('남성'),
                        value: 'M',
                        groupValue: _selectedGender,
                        onChanged: (v) => setState(() => _selectedGender = v!),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('여성'),
                        value: 'F',
                        groupValue: _selectedGender,
                        onChanged: (v) => setState(() => _selectedGender = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                onPressed: _isConnected ? _disconnect : _connect,
                icon: Icon(_isConnected ? Icons.link_off : Icons.link),
                label: Text(_isConnected ? '연결 해제' : '룸 입장하기'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              ),
              if (_isConnected) ...[
                const SizedBox(height: 16),
                _StatusCard(
                  status: _status ?? '-',
                  roomCode: _roomCode ?? '-',
                  nickname: myInfo?['name'] ?? '-',
                  team: myTeam,
                ),
                const SizedBox(height: 20),
                Text('✨ 비밀 지목 (이성만 표시됨)', style: Theme.of(context).textTheme.titleLarge),
                const Text('마음에 드는 분을 찍어주세요. 전원 투표 완료 시 자리가 공개됩니다!', style: TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 16),
                if (potentialMatches.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        '상대 팀원이 아직 입장하지 않았습니다.\n모두 입장하면 투표를 시작해 주세요!',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: potentialMatches.map<Widget>((p) {
                      final isSelected = _selectedTargetId == p['id'];
                      return ChoiceChip(
                        label: Text('${p['name']}', style: const TextStyle(fontSize: 18)),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) _pickParticipant(p['id']);
                        },
                        selectedColor: Colors.pink.shade100,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 40),
                const Divider(),
                const SizedBox(height: 20),
                const Text(
                  '💡 안내\n모든 참가자가 투표를 마쳐야 결과가 공개됩니다.\n결과는 무작위 순서로 발표되어 익명성이 보장됩니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.roomCode, required this.nickname, this.team});
  final String status;
  final String roomCode;
  final String nickname;
  final String? team;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _InfoItem(label: '룸코드', value: roomCode),
            _InfoItem(label: '닉네임', value: nickname),
            _InfoItem(label: '나의 팀', value: team ?? '-', color: team == '남성' ? Colors.blue : Colors.red),
          ],
        ),
      ),
    );
  }
}



class _InfoItem extends StatelessWidget {
  const _InfoItem({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
