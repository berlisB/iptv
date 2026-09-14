/// Parcours de connexion Telegram et choix du canal, en une seule feuille.
///
/// Le contenu suit l'état d'authentification plutôt que d'enchaîner des écrans :
/// Telegram peut réclamer le mot de passe 2FA APRÈS le code, ou rendre la main
/// directement si la session est encore valide. Un flux linéaire à étapes
/// fixes se désynchroniserait de la réalité.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:iptv/config/theme/color/app_color.dart';
import 'package:iptv/config/theme/typography/app_typography.dart';
import 'package:iptv/features/telegram/data/telegram_service.dart';
import 'package:iptv/features/telegram/provider/telegram_provider.dart';

Future<void> showTelegramSetup(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColor.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const TelegramSetupSheet(),
    );

class TelegramSetupSheet extends StatefulWidget {
  const TelegramSetupSheet({super.key});

  @override
  State<TelegramSetupSheet> createState() => _TelegramSetupSheetState();
}

class _TelegramSetupSheetState extends State<TelegramSetupSheet> {
  final _input = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _submit(TelegramProvider tg) async {
    final value = _input.text.trim();
    if (value.isEmpty || _busy) return;
    setState(() => _busy = true);

    final ok = switch (tg.authState) {
      TelegramAuthState.waitPhone => await tg.submitPhone(value),
      TelegramAuthState.waitCode => await tg.submitCode(value),
      TelegramAuthState.waitPassword => await tg.submitPassword(value),
      TelegramAuthState.ready => await tg.setChannel(value),
      _ => false,
    };

    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TelegramProvider>(
      builder: (context, tg, _) {
        final step = _stepFor(tg);
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            // Remonte la feuille au-dessus du clavier, sinon le champ de
            // saisie est masqué au moment précis où on doit y taper.
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.telegram,
                      color: AppColor.accentBlue, size: 26),
                  const SizedBox(width: 10),
                  Text('Canal Telegram',
                      style: AppTypography.heading3
                          .copyWith(color: AppColor.textPrimary)),
                ],
              ),
              const SizedBox(height: 8),
              Text(step.explanation,
                  style: AppTypography.caption
                      .copyWith(color: AppColor.textSecondary)),
              const SizedBox(height: 16),
              if (step.field != null) ...[
                TextField(
                  controller: _input,
                  autofocus: true,
                  enabled: !_busy,
                  keyboardType: step.keyboard,
                  obscureText: step.obscure,
                  inputFormatters: step.formatters,
                  style: AppTypography.body1
                      .copyWith(color: AppColor.textPrimary),
                  decoration: InputDecoration(
                    labelText: step.field,
                    hintText: step.hint,
                    labelStyle: AppTypography.caption
                        .copyWith(color: AppColor.textMuted),
                    hintStyle: AppTypography.caption
                        .copyWith(color: AppColor.textMuted),
                    filled: true,
                    fillColor: AppColor.surfaceColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _submit(tg),
                ),
                const SizedBox(height: 12),
              ],
              if (tg.error.isNotEmpty) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColor.accentRed, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(tg.error,
                          style: AppTypography.caption
                              .copyWith(color: AppColor.accentRed)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  if (step.field != null)
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : () => _submit(tg),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColor.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _busy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(step.action),
                      ),
                    ),
                  if (step.field == null)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Fermer'),
                      ),
                    ),
                ],
              ),
              if (tg.hasChannel) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    await tg.forgetChannel();
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.link_off,
                      size: 16, color: AppColor.textMuted),
                  label: Text('Changer de canal',
                      style: AppTypography.caption
                          .copyWith(color: AppColor.textMuted)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  _Step _stepFor(TelegramProvider tg) {
    if (!tg.isConfigured) {
      return const _Step(
        explanation:
            "L'app n'a pas été compilée avec des identifiants Telegram. "
            'Créez-en sur my.telegram.org (onglet API development tools), '
            'puis recompilez avec --dart-define=TELEGRAM_API_ID=… et '
            '--dart-define=TELEGRAM_API_HASH=…',
        action: 'Fermer',
      );
    }

    switch (tg.authState) {
      case TelegramAuthState.waitPhone:
        return const _Step(
          explanation: 'Connectez-vous avec votre compte Telegram. Les fichiers '
              'seront lus directement depuis les serveurs Telegram, sans passer '
              'par un serveur intermédiaire.',
          field: 'Numéro de téléphone',
          hint: '+33 6 12 34 56 78',
          keyboard: TextInputType.phone,
          action: 'Recevoir le code',
        );
      case TelegramAuthState.waitCode:
        return const _Step(
          explanation: 'Entrez le code que Telegram vient de vous envoyer.',
          field: 'Code de connexion',
          hint: '12345',
          keyboard: TextInputType.number,
          digitsOnly: true,
          action: 'Valider',
        );
      case TelegramAuthState.waitPassword:
        return const _Step(
          explanation: 'Votre compte utilise la vérification en deux étapes.',
          field: 'Mot de passe',
          obscure: true,
          action: 'Se connecter',
        );
      case TelegramAuthState.ready:
        return _Step(
          explanation: tg.hasChannel
              ? 'Connecté au canal @${tg.channel}. Indiquez un autre '
                  'identifiant pour en changer.'
              : "Indiquez l'identifiant public du canal contenant vos films.",
          field: 'Identifiant du canal',
          hint: '@mon_canal',
          action: tg.hasChannel ? 'Changer' : 'Connecter',
        );
      case TelegramAuthState.connecting:
        return const _Step(explanation: 'Connexion à Telegram…', action: '');
      case TelegramAuthState.failed:
        return const _Step(
          explanation: 'Telegram est indisponible. Vérifiez que la '
              'bibliothèque native est bien embarquée dans ce build.',
          action: 'Fermer',
        );
      case TelegramAuthState.idle:
      case TelegramAuthState.loggedOut:
        return const _Step(
          explanation: 'Session fermée. Rouvrez la section pour vous '
              'reconnecter.',
          action: 'Fermer',
        );
    }
  }
}

/// Ce qu'il faut afficher pour une étape donnée du parcours.
class _Step {
  final String explanation;
  final String? field;
  final String? hint;
  final TextInputType? keyboard;
  final bool obscure;
  final bool digitsOnly;
  final String action;

  const _Step({
    required this.explanation,
    this.field,
    this.hint,
    this.keyboard,
    this.obscure = false,
    this.digitsOnly = false,
    required this.action,
  });

  List<TextInputFormatter>? get formatters =>
      digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null;
}
