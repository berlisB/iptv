/// Navigation dans le contenu du canal Telegram, encastrée dans l'écran VOD.
///
/// Les affiches viennent de TMDB, résolues à la demande : afficher une grille
/// ne doit pas déclencher une requête par fichier du canal. Quand aucune fiche
/// ne correspond avec assez de certitude, on assume un visuel neutre plutôt
/// qu'une affiche fausse.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iptv/config/theme/color/app_color.dart';
import 'package:iptv/config/theme/typography/app_typography.dart';
import 'package:iptv/features/telegram/data/telegram_service.dart';
import 'package:iptv/features/telegram/domain/telegram_media.dart';
import 'package:iptv/features/telegram/presentation/telegram_player_screen.dart';
import 'package:iptv/features/telegram/presentation/telegram_setup_sheet.dart';
import 'package:iptv/features/telegram/provider/telegram_provider.dart';
import 'package:iptv/features/vod/domain/media_entity.dart';

class TelegramSection extends StatelessWidget {
  const TelegramSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TelegramProvider>(
      builder: (context, tg, _) {
        // Tant que la connexion ou le canal manquent, l'écran n'a rien à
        // montrer : on affiche l'action qui débloque, pas une liste vide.
        if (!tg.isConfigured || !tg.isReady || !tg.hasChannel) {
          return _Gate(tg: tg);
        }
        if (tg.isEmpty) {
          return tg.isIndexing
              ? _Indexing(found: tg.indexProgress)
              : _Empty(onRetry: tg.refreshIndex);
        }
        return _Browser(tg: tg);
      },
    );
  }
}

/// Écran d'accroche quand il manque une étape de configuration.
class _Gate extends StatelessWidget {
  final TelegramProvider tg;

  const _Gate({required this.tg});

  @override
  Widget build(BuildContext context) {
    final (message, action) = _stateOf(tg);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.telegram, size: 56, color: AppColor.accentBlue),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.body2
                  .copyWith(color: AppColor.textSecondary),
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => showTelegramSetup(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColor.primaryColor,
                ),
                icon: const Icon(Icons.link, size: 18),
                label: Text(action),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static (String, String?) _stateOf(TelegramProvider tg) {
    // Distinguer « fonctionnalité absente du build » de « mal configurée » :
    // sans ça, l'utilisateur croit à une erreur de sa part et cherche des
    // identifiants qui ne changeraient rien.
    if (!tg.isAvailable) {
      return (
        'La lecture depuis Telegram n\'est pas incluse dans cette version de '
            "l'app.",
        null,
      );
    }
    if (!tg.isConfigured) {
      return (
        "Cette version de l'app n'a pas été compilée avec des identifiants "
            'Telegram.',
        null,
      );
    }
    if (tg.authState == TelegramAuthState.failed) {
      return (tg.error.isNotEmpty ? tg.error : 'Telegram indisponible.', null);
    }
    if (!tg.isReady) {
      return (
        'Connectez votre compte Telegram pour accéder aux films du canal.',
        'Se connecter',
      );
    }
    return ('Choisissez le canal qui contient vos films.', 'Choisir le canal');
  }
}

class _Indexing extends StatelessWidget {
  final int found;

  const _Indexing({required this.found});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColor.primaryColor),
          const SizedBox(height: 16),
          Text(
            found > 0
                ? 'Indexation du canal… $found vidéos trouvées'
                : 'Lecture de l\'historique du canal…',
            style: AppTypography.caption
                .copyWith(color: AppColor.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onRetry;

  const _Empty({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.movie_filter_outlined,
              size: 48, color: AppColor.textMuted),
          const SizedBox(height: 12),
          Text('Aucune vidéo trouvée dans ce canal.',
              style: AppTypography.body2
                  .copyWith(color: AppColor.textSecondary)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Réindexer'),
          ),
        ],
      ),
    );
  }
}

/// Grille des films + liste des séries.
class _Browser extends StatelessWidget {
  final TelegramProvider tg;

  const _Browser({required this.tg});

  @override
  Widget build(BuildContext context) {
    final movies = tg.movies;
    final series = tg.series;

    return RefreshIndicator(
      onRefresh: tg.refreshIndex,
      color: AppColor.primaryColor,
      backgroundColor: AppColor.cardColor,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _header(context)),
          if (movies.isNotEmpty) ...[
            _sectionTitle('Films · ${movies.length}'),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 140,
                  childAspectRatio: 0.55,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 14,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _MediaCard(media: movies[i], tg: tg),
                  childCount: movies.length,
                ),
              ),
            ),
          ],
          if (series.isNotEmpty) ...[
            _sectionTitle('Séries · ${series.length}'),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _SeriesTile(series: series[i], tg: tg),
                childCount: series.length,
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
        child: Row(
          children: [
            const Icon(Icons.telegram, size: 16, color: AppColor.accentBlue),
            const SizedBox(width: 6),
            Expanded(
              child: Text('@${tg.channel}',
                  style: AppTypography.caption
                      .copyWith(color: AppColor.textSecondary)),
            ),
            if (tg.isIndexing)
              const SizedBox(
                height: 14,
                width: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColor.primaryColor),
              )
            else
              IconButton(
                icon: const Icon(Icons.refresh,
                    size: 18, color: AppColor.textMuted),
                onPressed: tg.refreshIndex,
                tooltip: 'Réindexer',
              ),
            IconButton(
              icon: const Icon(Icons.settings_outlined,
                  size: 18, color: AppColor.textMuted),
              onPressed: () => showTelegramSetup(context),
              tooltip: 'Configurer',
            ),
          ],
        ),
      );

  static SliverToBoxAdapter _sectionTitle(String label) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Text(label,
              style: AppTypography.heading3
                  .copyWith(color: AppColor.textPrimary, fontSize: 15)),
        ),
      );
}

/// Vignette d'un film, avec affiche TMDB si une correspondance est sûre.
class _MediaCard extends StatelessWidget {
  final TelegramMedia media;
  final TelegramProvider tg;

  const _MediaCard({required this.media, required this.tg});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TelegramPlayerScreen(media: media),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: FutureBuilder<MediaEntity?>(
                future: tg.tmdbFor(media),
                // Évite le clignotement au scroll : la valeur déjà connue est
                // affichée dès la première frame de la reconstruction.
                initialData: tg.cachedTmdb(media),
                builder: (context, snap) {
                  final poster = snap.data?.fullPosterUrl ?? '';
                  if (poster.isEmpty) return const _PosterFallback();
                  return CachedNetworkImage(
                    imageUrl: poster,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    placeholder: (_, _) => const _PosterFallback(),
                    errorWidget: (_, _, _) => const _PosterFallback(),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            media.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption
                .copyWith(color: AppColor.textPrimary, fontSize: 11),
          ),
          Text(
            [
              if (media.year > 0) '${media.year}',
              if (media.quality.isNotEmpty) media.quality,
              if (media.readableSize.isNotEmpty) media.readableSize,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption
                .copyWith(color: AppColor.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) => Container(
        color: AppColor.cardColor,
        child: const Center(
          child: Icon(Icons.movie_outlined,
              color: AppColor.textMuted, size: 28),
        ),
      );
}

/// Une série, dépliable saison par saison.
class _SeriesTile extends StatelessWidget {
  final TelegramSeries series;
  final TelegramProvider tg;

  const _SeriesTile({required this.series, required this.tg});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: const Icon(Icons.tv_outlined, color: AppColor.accentBlue),
        title: Text(series.title,
            style:
                AppTypography.body2.copyWith(color: AppColor.textPrimary)),
        subtitle: Text(
          '${series.episodes.length} épisodes · '
          '${series.seasons.length} saison(s)',
          style: AppTypography.caption.copyWith(color: AppColor.textMuted),
        ),
        children: [
          for (final season in series.seasons)
            ...series.episodesOf(season).map(
                  (e) => ListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.only(left: 56, right: 16),
                    title: Text(
                      'S${season.toString().padLeft(2, '0')}'
                      'E${e.episode.toString().padLeft(2, '0')}',
                      style: AppTypography.caption
                          .copyWith(color: AppColor.textSecondary),
                    ),
                    trailing: Text(
                      e.readableSize,
                      style: AppTypography.caption
                          .copyWith(color: AppColor.textMuted, fontSize: 10),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TelegramPlayerScreen(media: e),
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}
