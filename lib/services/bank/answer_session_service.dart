/// 本地答题进行态服务（F19）。
///
/// 进行态 key `answer.session.<mode>.<setId>`，练习与考试分开；断点恢复 /
/// 续答使用。服务端会话接口就绪前由本地 kv 承担（`main.dart` 装配
/// `KvAnswerSessionService`，背后是 shared_preferences）。
library;

import 'dart:convert';

import '../../core/kv_store.dart';
import '../../core/service_locator.dart';
import '../../models/answer_session_state.dart';

abstract class AnswerSessionService {
  AnswerSessionState? load({required String setId, required String mode});

  void save(AnswerSessionState state);

  void clear({required String setId, required String mode});
}

class KvAnswerSessionService implements AnswerSessionService {
  KvAnswerSessionService({KvStore? kvStore})
    : _kv = kvStore ?? ServiceLocator.kvStore;

  final KvStore _kv;

  @override
  AnswerSessionState? load({required String setId, required String mode}) {
    final raw = _kv.getString(KvStore.answerSessionKey(mode, setId));
    if (raw == null || raw.isEmpty) return null;
    try {
      return AnswerSessionState.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void save(AnswerSessionState state) {
    _kv.setString(
      KvStore.answerSessionKey(state.mode, state.setId),
      jsonEncode(state.toJson()),
    );
  }

  @override
  void clear({required String setId, required String mode}) {
    _kv.remove(KvStore.answerSessionKey(mode, setId));
  }
}
