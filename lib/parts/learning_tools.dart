import 'dart:math';
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final Random _random = Random();

/// CLASS-BASED QUIZ
class Question {
  final String question;
  final List<String> options;
  final int answerIndex;
  final String explanation;

  Question({
    required this.question,
    required this.options,
    required this.answerIndex,
    required this.explanation,
  });
}

// Fixed question pool
final List<Question> questionPool = [
  Question(
    question: "What does JVM stand for in Java?",
    options: [
      "Java Variable Machine",
      "Java Virtual Machine",
      "Joint Virtual Method",
      "Java Verified Mode",
    ],
    answerIndex: 1,
    explanation:
        "JVM = Java Virtual Machine. It allows Java programs to run on any platform.",
  ),
  Question(
    question: "Which symbol is used for comments in Python?",
    options: ["//", "#", "/* */", "--"],
    answerIndex: 1,
    explanation: "Python uses # for single-line comments.",
  ),
  Question(
    question: "VB.NET is mainly used with which framework?",
    options: [".NET Framework", "JVM", "Django", "Spring Boot"],
    answerIndex: 0,
    explanation:
        "VB.NET runs on the .NET Framework, making it tightly integrated with Microsoft tools.",
  ),
];

// Generate quiz from pool
List<Question> generateFixedQuiz(int count) {
  final shuffled = List<Question>.from(questionPool)..shuffle(_random);
  return shuffled.take(min(count, questionPool.length)).toList();
}

/// TEMPLATE-BASED QUIZ
final List<String> _templates = [
  "Which language is best known for {trait}?",
  "Which language commonly uses {feature}?",
  "Which language is strongly associated with {platform}?",
];

final Map<String, Map<String, List<String>>> _langData = {
  "Java": {
    "trait": ["object-oriented programming", "write once, run anywhere"],
    "feature": ["JVM bytecode", "strong typing"],
    "platform": ["enterprise apps", "Android development"],
  },
  "Python": {
    "trait": ["simplicity", "readability", "data science"],
    "feature": ["indentation syntax", "dynamic typing"],
    "platform": ["AI/ML", "web development"],
  },
  "VB.NET": {
    "trait": ["integration with .NET", "ease of use"],
    "feature": ["CLR execution", "Windows forms"],
    "platform": [".NET framework", "Microsoft ecosystem"],
  },
};

// Template-based random quiz generator
List<Map<String, Object>> generateQuiz(int count) {
  final questions = <Map<String, Object>>[];

  for (int i = 0; i < count; i++) {
    final lang = _langData.keys.elementAt(_random.nextInt(_langData.length));
    final category = _langData[lang]!.keys.elementAt(
      _random.nextInt(_langData[lang]!.keys.length),
    );
    final value =
        _langData[lang]![category]![_random.nextInt(
          _langData[lang]![category]!.length,
        )];

    final template = _templates[_random.nextInt(_templates.length)];
    final question = template.replaceAll("{$category}", value);

    final answers = _langData.keys.toList()..shuffle();
    final correct = lang;

    questions.add({
      "question": question,
      "answers": answers,
      "correct": correct,
    });
  }

  return questions;
}

/// LEARNING TOOLS WIDGET
class LearningTools extends StatefulWidget {
  const LearningTools({super.key});

  @override
  State<LearningTools> createState() => _LearningToolsState();
}

class _LearningToolsState extends State<LearningTools> {
  bool _isLoading = true;

  List<Map<String, dynamic>> _articles = [];
  List<Map<String, dynamic>> _quizQuestions = [];
  Map<String, List<String>> _videoIds =
      {}; // Changed to support multiple videos per language
  final Map<String, List<YoutubePlayerController>> _videoControllers =
      {}; // Changed to support multiple controllers

  int _quizIndex = 0;
  int _score = 0;
  bool _quizFinished = false;
  String? _selectedAnswer;
  bool _showAnswerFeedback = false;

  // Enhanced article content
  final List<Map<String, String>> _fallbackArticles = [
    {
      'title': 'Java',
      'content': '''
Java is a general-purpose, class-based, object-oriented programming language.

📌 Key Features:
- Runs on the JVM (Write Once, Run Anywhere)
- Strong typing and large standard library
- Multithreading support

💻 Common Uses:
- Android app development
- Enterprise systems
- Backend web services

✅ Strengths:
- Cross-platform
- Mature ecosystem
- High performance
    ''',
    },
    {
      'title': 'Python',
      'content': '''
Python is an interpreted, high-level programming language designed for simplicity.

📌 Key Features:
- Indentation-based syntax
- Dynamic typing
- Vast library support

💻 Common Uses:
- Artificial Intelligence & Data Science
- Web Development
- Scripting & Automation

✅ Strengths:
- Beginner friendly
- Huge community
- Excellent for prototyping
    ''',
    },
    {
      'title': 'VB.NET',
      'content': '''
VB.NET (Visual Basic .NET) is a multi-paradigm language built on the .NET framework.

📌 Key Features:
- Object-oriented and event-driven
- Strong integration with Microsoft products
- Easy transition from older VB versions

💻 Common Uses:
- Windows Forms & WPF apps
- Enterprise tools in Microsoft ecosystem
- Desktop automation

✅ Strengths:
- Simplified syntax
- Rapid application development
- Tight integration with Visual Studio
    ''',
    },
  ];

  @override
  void initState() {
    super.initState();
    _quizQuestions = generateQuiz(10);
    _loadContent();
  }

  @override
  void dispose() {
    for (final controllerList in _videoControllers.values) {
      for (final controller in controllerList) {
        controller.close();
      }
    }
    super.dispose();
  }

  Future<void> _loadContent() async {
    try {
      final client = Supabase.instance.client;
      final articlesResponse = await client.from('articles').select();
      final videosResponse = await client.from('videos').select();
      final quizResponse = await client.from('quizzes').select();

      setState(() {
        _articles = List<Map<String, dynamic>>.from(articlesResponse);

        // Process videos - group by language
        _videoIds = {};
        for (var v in videosResponse) {
          final lang = v['title'] as String;
          final videoId = v['youtube_id'] as String;

          if (!_videoIds.containsKey(lang)) {
            _videoIds[lang] = [];
          }
          _videoIds[lang]!.add(videoId);
        }

        _quizQuestions = List<Map<String, dynamic>>.from(quizResponse);
        _quizQuestions.shuffle(Random());
        _createVideoControllers();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        // Use enhanced fallback articles
        _articles = _fallbackArticles;

        // Multiple videos per language for demonstration
        _videoIds = {
          'Java': ['grEKMHGYyns', 'm-5NkCgFz-s', 'WPvGqX-TXP0'],
          'Python': ['rfscVS0vtbw', 'kqtD5dpn9C8', 'JJmcL1N2KQs'],
          'VB.NET': ['m3g8Ma0Tye0', 'F3Fk6s7LQ_c', 'F3Fk6s7LQ_c'],
        };

        _quizQuestions = generateQuiz(10);
        _createVideoControllers();
        _isLoading = false;
      });
    }
  }

  void _createVideoControllers() {
    for (final lang in _videoIds.keys) {
      if (!_videoControllers.containsKey(lang)) {
        _videoControllers[lang] = [];
      }

      for (final id in _videoIds[lang]!) {
        final controller = YoutubePlayerController(
          params: const YoutubePlayerParams(
            showFullscreenButton: true,
            mute: true,
            playsInline: false,
            strictRelatedVideos: true,
          ),
        )..loadVideoById(videoId: id);

        _videoControllers[lang]!.add(controller);
      }
    }
  }

  void _answerQuestion(String answer) {
    if (_quizFinished) return;

    setState(() {
      _selectedAnswer = answer;
      _showAnswerFeedback = true;
    });

    final correct = _quizQuestions[_quizIndex]['correct'] as String;
    if (answer == correct) _score++;

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _showAnswerFeedback = false;
          _selectedAnswer = null;
          _quizIndex++;
          if (_quizIndex >= _quizQuestions.length) _quizFinished = true;
        });
      }
    });
  }

  void _resetQuiz() {
    setState(() {
      _quizIndex = 0;
      _score = 0;
      _quizFinished = false;
      _quizQuestions.shuffle(Random());
    });
  }

  Widget _buildArticleCard(Map<String, dynamic> article) {
    String title = article['title']?.toString() ?? "";
    String content = article['content']?.toString() ?? "";
    String preview =
        content.length > 80 ? "${content.substring(0, 80)}..." : content;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          preview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, color: Colors.grey),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              content,
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoSection(String title, List<String> videoIds) {
    final controllers = _videoControllers[title] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title Tutorials',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: PageView.builder(
            itemCount: controllers.length,
            itemBuilder: (context, index) {
              final controller = controllers[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.3),
                        blurRadius: 5,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: YoutubePlayer(
                      controller: controller,
                      aspectRatio: 16 / 9,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildQuizQuestion() {
    if (_quizQuestions.isEmpty) {
      return const Text('No quiz questions available.');
    }

    final q = _quizQuestions[_quizIndex];
    final correctAnswer = q['correct'] as String;
    final isCorrect = _selectedAnswer == correctAnswer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Question ${_quizIndex + 1} of ${_quizQuestions.length}',
          style: const TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.indigo[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            q['question'] as String,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.indigo,
            ),
          ),
        ),
        const SizedBox(height: 16),
        ...(q['answers'] as List).map((ans) {
          final isSelected = _selectedAnswer == ans;
          final isActuallyCorrect = ans == correctAnswer;

          Color buttonColor = Colors.indigo;
          if (_showAnswerFeedback) {
            if (isSelected) {
              buttonColor = isCorrect ? Colors.green : Colors.red;
            } else if (isActuallyCorrect) {
              buttonColor = Colors.green;
            }
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: ElevatedButton(
              onPressed:
                  _showAnswerFeedback
                      ? null
                      : () => _answerQuestion(ans.toString()),
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(ans.toString()),
            ),
          );
        }),
        if (_showAnswerFeedback) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isCorrect ? Colors.green[50] : Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isCorrect ? Colors.green : Colors.red),
            ),
            child: Text(
              isCorrect
                  ? 'Correct! Well done!'
                  : 'Incorrect. The correct answer is: $correctAnswer',
              style: TextStyle(
                color: isCorrect ? Colors.green[800] : Colors.red[800],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildQuizResult() {
    final percentage = (_score / _quizQuestions.length) * 100;
    final isGoodScore = percentage >= 70;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isGoodScore ? Colors.green[50] : Colors.orange[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isGoodScore ? Colors.green : Colors.orange,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quiz Completed!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isGoodScore ? Colors.green[800] : Colors.orange[800],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your score: $_score / ${_quizQuestions.length} (${percentage.toStringAsFixed(1)}%)',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                isGoodScore
                    ? 'Great job! You have a good understanding of the material.'
                    : 'Keep practicing! You\'ll improve with more study.',
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton(
            onPressed: _resetQuiz,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Try Again'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3, // 📌 3 partitions
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Learning Tools'),
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.article), text: 'Articles'),
              Tab(icon: Icon(Icons.video_library), text: 'Videos'),
              Tab(icon: Icon(Icons.quiz), text: 'Quiz'),
            ],
          ),
        ),
        body:
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                  children: [
                    // 📰 Articles partition
                    ListView(
                      padding: const EdgeInsets.all(16),
                      children:
                          _articles
                              .map((article) => _buildArticleCard(article))
                              .toList(),
                    ),

                    // 🎥 Videos partition
                    ListView(
                      padding: const EdgeInsets.all(16),
                      children:
                          _videoIds.entries
                              .map(
                                (entry) =>
                                    _buildVideoSection(entry.key, entry.value),
                              )
                              .toList(),
                    ),

                    // 📝 Quiz partition
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _quizFinished
                              ? _buildQuizResult()
                              : _buildQuizQuestion(),
                          const SizedBox(height: 20),
                          LinearProgressIndicator(
                            value:
                                _quizFinished
                                    ? 1.0
                                    : _quizIndex / _quizQuestions.length,
                            backgroundColor: Colors.grey[300],
                            color: Colors.indigo,
                            minHeight: 12,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _quizFinished
                                ? 'Completed! Score: $_score/${_quizQuestions.length}'
                                : 'Progress: $_quizIndex/${_quizQuestions.length} questions',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
      ),
    );
  }
}
