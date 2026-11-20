import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Voice input sheet: listens (English-India by default, Bangla on tap),
/// shows the words live and lets the user correct them before using them.
/// Typing works too, so the sheet is useful even without a microphone.
class VoiceSheet extends StatefulWidget {
  final String title, hint;
  const VoiceSheet({super.key, required this.title, required this.hint});

  /// The final text, or null when cancelled.
  static Future<String?> listen(BuildContext context, {String title = 'Speak the bill', String hint = ''}) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => VoiceSheet(title: title, hint: hint),
      );

  @override
  State<VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<VoiceSheet> with SingleTickerProviderStateMixin {
  final _speech = SpeechToText();
  final _text = TextEditingController();
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  bool _ready = false, _listening = false;
  String? _error;
  String _locale = 'en_IN';
  double _level = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _speech.cancel();
    _pulse.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      _ready = await _speech.initialize(
        onError: (e) => mounted ? setState(() {
          _listening = false;
          _error = e.errorMsg.contains('no_match') || e.errorMsg.contains('speech_timeout')
              ? 'Didn\'t catch that — tap the mic and speak again'
              : 'Voice error (${e.errorMsg}) — you can type instead';
        }) : null,
        onStatus: (s) => mounted ? setState(() => _listening = s == 'listening') : null,
      );
    } catch (_) {
      _ready = false;
    }
    if (!mounted) return;
    if (!_ready) {
      setState(() => _error = 'Voice input is not available on this phone — type the bill instead');
      return;
    }
    await _listen();
  }

  Future<void> _listen() async {
    if (!_ready) return;
    HapticFeedback.mediumImpact();
    setState(() => _error = null);
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) {
        if (!mounted) return;
        setState(() => _text.text = r.recognizedWords);
        if (r.finalResult) setState(() => _listening = false);
      },
      onSoundLevelChange: (l) => mounted ? setState(() => _level = l) : null,
      listenOptions: SpeechListenOptions(
        localeId: _locale,
        partialResults: true,
        cancelOnError: true,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        listenMode: ListenMode.dictation,
      ),
    );
    if (mounted) setState(() => _listening = true);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.all(10),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 18 + bottom),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(colors: [Color(0xFF1B2163), Color(0xFF4318D2)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: const [BoxShadow(color: Color(0x664318D2), blurRadius: 30, offset: Offset(0, 10))],
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 42, height: 4, decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 14),
          Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFD27A), size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800))),
            _lang('EN', 'en_IN'),
            const SizedBox(width: 6),
            _lang('বাং', 'bn_IN'),
          ]),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: _listening ? () => _speech.stop() : _listen,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, child) {
                final grow = _listening ? 10 + _pulse.value * 10 + (_level.clamp(0, 10)) * 2 : 0.0;
                return Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _listening ? const Color(0xFFFF4D6D) : Colors.white,
                    boxShadow: [BoxShadow(color: (_listening ? const Color(0xFFFF4D6D) : Colors.white).withAlpha(0x55), blurRadius: 20, spreadRadius: grow)],
                  ),
                  child: child,
                );
              },
              child: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded, size: 42, color: _listening ? Colors.white : const Color(0xFF4318D2)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _error ?? (_listening ? 'Listening…' : _ready ? 'Tap the mic to speak' : 'Starting…'),
            textAlign: TextAlign.center,
            style: TextStyle(color: _error != null ? const Color(0xFFFFD27A) : Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(18)),
            child: TextField(
              controller: _text,
              minLines: 2,
              maxLines: 4,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: widget.hint,
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
              ),
            ),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF4318D2),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _text.text.trim().isEmpty
                    ? null
                    : () {
                        _speech.stop();
                        Navigator.pop(context, _text.text.trim());
                      },
                icon: const Icon(Icons.bolt_rounded),
                label: const Text('Make it', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _lang(String label, String id) {
    final on = _locale == id;
    return GestureDetector(
      onTap: () async {
        if (on) return;
        await _speech.stop();
        setState(() => _locale = id);
        await _listen();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? Colors.white : const Color(0x26FFFFFF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label, style: TextStyle(color: on ? const Color(0xFF4318D2) : Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
      ),
    );
  }
}
