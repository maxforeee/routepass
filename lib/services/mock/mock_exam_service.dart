/// ExamService 的 Mock 实现（规格文档第 4 章 §4.4.3）。
///
/// 本地用样例题组卷，不判真分；交卷 score 一律为 null，页面显示“样例考试，不计分”。
library;

import '../../models/exam.dart';
import '../bank/exam_service.dart';
import 'sample_data.dart';

class MockExamService implements ExamService {
  @override
  Future<ExamSession> startExam({required int drawCount}) async {
    final questions = await SampleData.loadSampleQuestions();
    final picked = questions.length > drawCount
        ? questions.sublist(0, drawCount)
        : questions;
    return ExamSession(
      id: 'MOCK-EXAM-10',
      started_at: DateTime.now().millisecondsSinceEpoch,
      total: picked.length,
      detail: '样例考试',
      snapshot: picked
          .map(
            (q) => ExamSnapshot(
              stem: q.stem,
              options: q.options,
              answer: <String>[],
              analysis: '',
            ),
          )
          .toList(),
    );
  }

  @override
  Future<ExamResult?> submitExam({
    required String examId,
    required Map<String, List<String>> answers,
    required int durationMs,
  }) async {
    // Mock 不判真分：score 一律为 null，绝不许用假答案算出假分数。
    return ExamResult(
      score: null,
      passed: null,
      detail: '样例考试，不计分',
    );
  }

  @override
  Future<ExamSession?> getExam(String examId) async {
    return null;
  }

  @override
  Future<List<ExamSession>> getHistory() async {
    return <ExamSession>[];
  }
}
