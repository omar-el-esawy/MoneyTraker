import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/services/app_update.dart';
import 'package:money_traker/services/app_update_logic.dart';

class ForceUpdatePage extends StatelessWidget {
  final UpdateOffer offer;

  const ForceUpdatePage({super.key, required this.offer});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: UpdatePrompt(offer: offer, blocking: true),
    );
  }
}

Future<void> showOptionalUpdateDialog(BuildContext context, UpdateOffer offer) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return Dialog(child: UpdatePrompt(offer: offer, blocking: false));
    },
  );
}

class UpdatePrompt extends StatefulWidget {
  final UpdateOffer offer;
  final bool blocking;

  const UpdatePrompt({super.key, required this.offer, required this.blocking});

  @override
  State<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends State<UpdatePrompt>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _awaitingPermission = false;
  double? _progress;
  String? _error;
  File? _apk;

  bool get _arabic => Localizations.localeOf(context).languageCode == 'ar';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_awaitingPermission) return;
    _awaitingPermission = false;
    final file = _apk;
    if (file == null) return;
    unawaited(_openIfAllowed(file));
  }

  Future<void> _openIfAllowed(File file) async {
    final allowed = await AppUpdateService.canRequestPackageInstalls();
    if (!mounted || !allowed) return;
    await _openDownloaded(file);
  }

  Future<void> _start() async {
    if (_busy) return;
    final existing = _apk;
    if (existing != null) {
      await _openDownloaded(existing);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      final file = await AppUpdateService.downloadApk(
        widget.offer.downloadUrl,
        (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() => _apk = file);
      await _openDownloaded(file);
    } catch (e, stack) {
      debugPrint('Update download failed: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _error = _arabic
            ? 'متعذر تحميل التحديث. تأكد من النت وحاول تاني.'
            : 'Could not download the update. Check the connection and try again.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDownloaded(File file) async {
    final result = await AppUpdateService.openApk(file);
    if (!mounted) return;
    switch (result) {
      case InstallStart.opened:
        setState(() => _error = null);
      case InstallStart.needsPermission:
        setState(() {
          _error = _arabic
              ? 'اسمح للتطبيق إنه يثبّت التحديثات، وبعدين ارجع هنا.'
              : 'Allow this app to install updates, then come back here.';
        });
        _awaitingPermission = true;
        try {
          await AppUpdateService.openInstallPermissionSettings();
        } catch (e) {
          debugPrint('Could not open install settings: $e');
          _awaitingPermission = false;
        }
      case InstallStart.failed:
        setState(() {
          _error = _arabic
              ? 'الملف اتحمل، بس متعذر فتح شاشة التثبيت.'
              : 'The file downloaded, but the installer could not be opened.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final arabic = _arabic;
    final title = widget.blocking
        ? (arabic ? 'لازم تحدّث التطبيق' : 'Update required')
        : (arabic ? 'في تحديث جديد' : 'Update available');
    final latest = releaseLabel(widget.offer.version, widget.offer.buildNumber);
    final body = widget.blocking
        ? (arabic
              ? 'النسخة دي مش هتكمل من غير تحديث $latest.'
              : 'This version cannot continue without update $latest.')
        : (arabic ? 'آخر إصدار هو $latest.' : 'The latest is $latest.');

    final details = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.system_update_alt,
          size: widget.blocking ? 56 : 36,
          color: AppConstants.primaryColor,
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (widget.offer.changelog.isNotEmpty) ...[
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppConstants.backgroundColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                widget.offer.changelog,
                textAlign: arabic ? TextAlign.right : TextAlign.left,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppConstants.errorColor),
          ),
        ],
      ],
    );

    final actions = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_busy) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: _progress,
            color: AppConstants.primaryColor,
            backgroundColor: AppConstants.primarySurface,
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            if (!widget.blocking)
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: Text(arabic ? 'لاحقاً' : 'Later'),
              ),
            if (!widget.blocking) const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: _busy ? null : _start,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  _busy
                      ? (arabic ? 'جارٍ التحميل…' : 'Downloading…')
                      : widget.blocking
                      ? (arabic ? 'تحميل التحديث' : 'Download update')
                      : (arabic ? 'تحديث' : 'Update'),
                ),
              ),
            ),
          ],
        ),
      ],
    );

    final directed = Directionality(
      textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
      child: widget.blocking
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Center(child: SingleChildScrollView(child: details)),
                ),
                actions,
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [details, actions],
            ),
    );

    if (!widget.blocking) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: directed,
      );
    }

    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(24), child: directed),
      ),
    );
  }
}
