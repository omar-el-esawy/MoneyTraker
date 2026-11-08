import 'package:money_traker/sms/template_engine/sms_template_compiler.dart';
import 'package:money_traker/sms/template_engine/template_models.dart';

class SmsEnvelope {
  final String sender;
  final String body;
  final DateTime receivedAt;
  final String? multipartId;
  final int? partIndex;
  final int? partCount;

  const SmsEnvelope({
    required this.sender,
    required this.body,
    required this.receivedAt,
    this.multipartId,
    this.partIndex,
    this.partCount,
  });
}

class SmsUnrecognizedMessage {
  final String bankId;
  final SmsEnvelope message;

  const SmsUnrecognizedMessage({required this.bankId, required this.message});
}

enum SmsProcessingStatus {
  parsed,
  ignoredSender,
  unrecognized,
  duplicate,
  waitingForParts,
}

class SmsProcessingOutcome {
  final SmsProcessingStatus status;
  final SmsParsedResult? result;

  const SmsProcessingOutcome._({required this.status, this.result});

  bool get shouldNotify => status == SmsProcessingStatus.unrecognized;

  static SmsProcessingOutcome parsed(SmsParsedResult result) {
    return SmsProcessingOutcome._(
      status: SmsProcessingStatus.parsed,
      result: result,
    );
  }

  static const ignoredSender = SmsProcessingOutcome._(
    status: SmsProcessingStatus.ignoredSender,
  );

  static const unrecognized = SmsProcessingOutcome._(
    status: SmsProcessingStatus.unrecognized,
  );

  static const duplicate = SmsProcessingOutcome._(
    status: SmsProcessingStatus.duplicate,
  );

  static const waitingForParts = SmsProcessingOutcome._(
    status: SmsProcessingStatus.waitingForParts,
  );
}

class SmsTemplatePreview {
  final int total;
  final int matched;
  final List<SmsParsedResult> samples;

  const SmsTemplatePreview({
    required this.total,
    required this.matched,
    required this.samples,
  });
}

class SmsBankTemplateSet {
  final String bankId;
  final List<String> senderIds;
  final List<CompiledSmsTemplate> _templates;

  const SmsBankTemplateSet._({
    required this.bankId,
    required this.senderIds,
    required List<CompiledSmsTemplate> templates,
  }) : _templates = templates;

  static SmsBankTemplateSet? compile({
    required String bankId,
    required List<String> senderIds,
    required List<SmsTemplate> templates,
  }) {
    final normalizedSenders = senderIds
        .map((sender) => sender.trim())
        .where((sender) => sender.isNotEmpty)
        .toSet()
        .toList();
    if (bankId.trim().isEmpty ||
        normalizedSenders.isEmpty ||
        templates.isEmpty ||
        templates.any((template) => template.bankId != bankId)) {
      return null;
    }

    final compiled = <({int order, CompiledSmsTemplate template})>[];
    for (var i = 0; i < templates.length; i++) {
      final template = SmsTemplateCompiler.compile(templates[i]);
      if (template == null) return null;
      compiled.add((order: i, template: template));
    }
    compiled.sort((a, b) {
      final bySpecificity = b.template.specificity.compareTo(
        a.template.specificity,
      );
      if (bySpecificity != 0) return bySpecificity;
      return a.order.compareTo(b.order);
    });

    return SmsBankTemplateSet._(
      bankId: bankId,
      senderIds: List.unmodifiable(normalizedSenders),
      templates: List.unmodifiable([
        for (final item in compiled) item.template,
      ]),
    );
  }

  bool acceptsSender(String sender) {
    final candidate = sender.trim().toLowerCase();
    return senderIds.any((item) => item.toLowerCase() == candidate);
  }

  SmsParsedResult? match(String body) {
    for (final template in _templates) {
      final result = template.match(body);
      if (result != null) return result;
    }
    return null;
  }

  SmsTemplatePreview preview(
    String templateId,
    List<SmsEnvelope> messages, {
    int sampleLimit = 5,
  }) {
    CompiledSmsTemplate? selected;
    for (final template in _templates) {
      if (template.template.id == templateId) selected = template;
    }
    final bankMessages = messages
        .where((message) => acceptsSender(message.sender))
        .toList();
    if (selected == null) {
      return SmsTemplatePreview(
        total: bankMessages.length,
        matched: 0,
        samples: const [],
      );
    }

    final results = <SmsParsedResult>[];
    var matched = 0;
    for (final message in bankMessages) {
      final result = selected.match(message.body);
      if (result == null) continue;
      matched++;
      if (results.length < sampleLimit) results.add(result);
    }
    return SmsTemplatePreview(
      total: bankMessages.length,
      matched: matched,
      samples: List.unmodifiable(results),
    );
  }
}

class SmsTemplateEngine {
  final List<SmsBankTemplateSet> banks;
  final List<SmsUnrecognizedMessage> _unrecognized = [];
  final Map<String, _MultipartBuffer> _multipartBuffers = {};
  final List<SmsEnvelope> _seenMessages = [];

  SmsTemplateEngine({required List<SmsBankTemplateSet> banks})
    : banks = List.unmodifiable(banks);

  List<SmsUnrecognizedMessage> get unrecognizedMessages =>
      List.unmodifiable(_unrecognized);

  SmsProcessingOutcome process(SmsEnvelope message) {
    final bank = _bankForSender(message.sender);
    if (bank == null) return SmsProcessingOutcome.ignoredSender;

    final assembled = _assemble(message);
    if (assembled.invalid) {
      _saveUnrecognized(bank, message);
      return SmsProcessingOutcome.unrecognized;
    }
    final complete = assembled.message;
    if (complete == null) return SmsProcessingOutcome.waitingForParts;
    if (_isDuplicate(complete)) return SmsProcessingOutcome.duplicate;
    _seenMessages.add(complete);

    final parsed = bank.match(complete.body);
    if (parsed != null) return SmsProcessingOutcome.parsed(parsed);

    _saveUnrecognized(bank, complete);
    return SmsProcessingOutcome.unrecognized;
  }

  SmsBankTemplateSet? _bankForSender(String sender) {
    for (final candidate in banks) {
      if (candidate.acceptsSender(sender)) {
        return candidate;
      }
    }
    return null;
  }

  void _saveUnrecognized(SmsBankTemplateSet bank, SmsEnvelope message) {
    _unrecognized.add(
      SmsUnrecognizedMessage(bankId: bank.bankId, message: message),
    );
  }

  ({SmsEnvelope? message, bool invalid}) _assemble(SmsEnvelope message) {
    final hasMultipartMetadata =
        message.multipartId != null ||
        message.partIndex != null ||
        message.partCount != null;
    if (!hasMultipartMetadata) return (message: message, invalid: false);

    final id = message.multipartId;
    final index = message.partIndex;
    final count = message.partCount;
    if (id == null ||
        id.trim().isEmpty ||
        index == null ||
        count == null ||
        count < 1 ||
        index < 0 ||
        index >= count) {
      return (message: null, invalid: true);
    }

    final key = '${message.sender.trim().toLowerCase()}|${id.trim()}';
    final buffer = _multipartBuffers.putIfAbsent(
      key,
      () => _MultipartBuffer(sender: message.sender, partCount: count),
    );
    if (buffer.partCount != count) {
      _multipartBuffers.remove(key);
      return (message: null, invalid: true);
    }
    final existing = buffer.parts[index];
    if (existing != null && existing.body != message.body) {
      _multipartBuffers.remove(key);
      return (message: null, invalid: true);
    }
    buffer.parts[index] = message;
    if (buffer.parts.length != count) {
      return (message: null, invalid: false);
    }

    final ordered = [for (var i = 0; i < count; i++) buffer.parts[i]];
    if (ordered.any((part) => part == null)) {
      return (message: null, invalid: false);
    }
    _multipartBuffers.remove(key);
    final parts = ordered.cast<SmsEnvelope>();
    final receivedAt = parts
        .map((part) => part.receivedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return (
      message: SmsEnvelope(
        sender: buffer.sender,
        body: parts.map((part) => part.body).join(),
        receivedAt: receivedAt,
      ),
      invalid: false,
    );
  }

  bool _isDuplicate(SmsEnvelope message) {
    final sender = message.sender.trim().toLowerCase();
    const window = Duration(minutes: 2);
    return _seenMessages.any((seen) {
      if (seen.sender.trim().toLowerCase() != sender ||
          seen.body != message.body) {
        return false;
      }
      return seen.receivedAt.difference(message.receivedAt).abs() <= window;
    });
  }
}

class _MultipartBuffer {
  final String sender;
  final int partCount;
  final Map<int, SmsEnvelope> parts = {};

  _MultipartBuffer({required this.sender, required this.partCount});
}
