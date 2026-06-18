import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iptv/config/theme/color/app_color.dart';
import 'package:iptv/config/theme/typography/app_typography.dart';
import 'package:iptv/core/storage/app_storage.dart';
import 'package:iptv/features/home/data/datasources/xtream_service.dart';
import 'package:iptv/features/home/provider/home_provider.dart';

/// Tuile de gestion d'un abonnement Xtream Codes (ajout / suppression).
class XtreamSettingsTile extends StatefulWidget {
  const XtreamSettingsTile({super.key});

  @override
  State<XtreamSettingsTile> createState() => _XtreamSettingsTileState();
}

class _XtreamSettingsTileState extends State<XtreamSettingsTile> {
  @override
  Widget build(BuildContext context) {
    final config = AppStorage.getXtreamConfig();
    final connected = config != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColor.cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: Icon(connected ? Icons.cloud_done : Icons.cloud_outlined,
            color: connected ? AppColor.accentGreen : AppColor.primaryColor),
        title: Text(
          connected ? 'Abonnement connecté' : 'Ajouter un abonnement Xtream',
          style: AppTypography.body1,
        ),
        subtitle: Text(
          connected ? config['host']! : 'Serveur + identifiant + mot de passe',
          style: AppTypography.caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: connected
            ? IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColor.accentRed),
                onPressed: _disconnect,
              )
            : const Icon(Icons.chevron_right, color: AppColor.textMuted),
        onTap: connected ? null : _showForm,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Future<void> _disconnect() async {
    await AppStorage.clearXtreamConfig();
    if (!mounted) return;
    setState(() {});
    context.read<HomeProvider>().loadChannels();
  }

  void _showForm() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColor.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _XtreamForm(onSaved: () => setState(() {})),
    );
  }
}

class _XtreamForm extends StatefulWidget {
  final VoidCallback onSaved;
  const _XtreamForm({required this.onSaved});

  @override
  State<_XtreamForm> createState() => _XtreamFormState();
}

class _XtreamFormState extends State<_XtreamForm> {
  final _host = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _host.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final host = XtreamService.normalizeHost(_host.text);
    final ok = await XtreamService.validate(host, _user.text, _pass.text);
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _loading = false;
        _error = 'Identifiants invalides ou serveur injoignable';
      });
      return;
    }

    await AppStorage.setXtreamConfig(host, _user.text, _pass.text);
    widget.onSaved();
    if (!mounted) return;
    context.read<HomeProvider>().loadChannels();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Abonnement Xtream Codes', style: AppTypography.heading3),
          const SizedBox(height: 4),
          Text('Connectez votre abonnement IPTV personnel.',
              style: AppTypography.caption),
          const SizedBox(height: 16),
          _field(_host, 'Serveur (ex: http://mon-serveur.com:8080)'),
          const SizedBox(height: 10),
          _field(_user, 'Identifiant'),
          const SizedBox(height: 10),
          _field(_pass, 'Mot de passe', obscure: true),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: AppTypography.caption.copyWith(color: AppColor.accentRed)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColor.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Valider & connecter'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, {bool obscure = false}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      style: AppTypography.body2.copyWith(color: AppColor.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTypography.body2.copyWith(color: AppColor.textMuted),
        filled: true,
        fillColor: AppColor.cardColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
