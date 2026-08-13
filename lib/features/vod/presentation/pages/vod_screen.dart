import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iptv/config/theme/color/app_color.dart';
import 'package:iptv/config/theme/typography/app_typography.dart';
import 'package:iptv/common/widgets/loading_shimmer.dart';
import 'package:iptv/core/storage/app_storage.dart';
import 'package:iptv/features/vod/domain/media_entity.dart';
import 'package:iptv/features/vod/domain/anime_entity.dart';
import 'package:iptv/features/vod/presentation/pages/vod_player_screen.dart';
import 'package:iptv/features/vod/provider/vod_provider.dart';

/// Écran VOD (Films, Séries & Animés).
class VodScreen extends StatefulWidget {
  const VodScreen({super.key});

  @override
  State<VodScreen> createState() => _VodScreenState();
}

class _VodScreenState extends State<VodScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VodProvider>().loadAll();
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      context.read<VodProvider>().loadMore();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.surfaceColor,
      body: SafeArea(
        child: Consumer<VodProvider>(
          builder: (context, vod, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                _buildSearchBar(vod),
                _buildCategoryChips(vod),
                const SizedBox(height: 8),
                Expanded(
                  child: vod.isLoading
                      ? const LoadingShimmer()
                      : vod.selectedCategory == VodCategory.anime
                          ? _buildAnimeSection(vod)
                          : vod.searchQuery.isNotEmpty
                              ? _buildSearchResults(vod)
                              : _buildContent(vod),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColor.accentRed, AppColor.accentOrange],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.movie_outlined, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Films, Séries & Animés', style: AppTypography.heading3),
                Text('Gratuits en streaming', style: AppTypography.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(VodProvider vod) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextField(
        controller: _searchController,
        style: AppTypography.body2.copyWith(color: AppColor.textPrimary),
        onChanged: (q) => vod.search(q),
        decoration: InputDecoration(
          hintText: 'Rechercher film, série ou animé...',
          hintStyle: AppTypography.body2.copyWith(color: AppColor.textMuted),
          prefixIcon: const Icon(Icons.search, color: AppColor.textMuted, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    vod.search('');
                  },
                )
              : null,
          filled: true,
          fillColor: AppColor.cardColor,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChips(VodProvider vod) {
    final categories = [
      (VodCategory.trending, 'Tendances', Icons.trending_up),
      (VodCategory.popular, 'Populaires', Icons.star_outline),
      (VodCategory.movies, 'Films', Icons.movie_outlined),
      (VodCategory.tv, 'Séries', Icons.tv_outlined),
      (VodCategory.anime, 'Animés', Icons.animation_outlined),
      (VodCategory.action, 'Action', Icons.local_fire_department_outlined),
      (VodCategory.comedy, 'Comédie', Icons.emoji_emotions_outlined),
      (VodCategory.drama, 'Drame', Icons.theater_comedy_outlined),
      (VodCategory.horror, 'Horreur', Icons.bloodtype_outlined),
    ];

    return SizedBox(
      height: 42,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final (cat, label, icon) = categories[index];
          final isSelected = vod.selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: isSelected ? Colors.white : AppColor.textMuted),
                  const SizedBox(width: 4),
                  Text(label),
                ],
              ),
              labelStyle: AppTypography.caption.copyWith(
                color: isSelected ? Colors.white : AppColor.textMuted,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
              selected: isSelected,
              onSelected: (_) => vod.setCategory(cat),
              backgroundColor: AppColor.cardColor,
              selectedColor: AppColor.primaryColor,
              side: BorderSide.none,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchResults(VodProvider vod) {
    if (vod.isSearching) {
      return const Center(child: CircularProgressIndicator(color: AppColor.primaryColor));
    }

    final hasTmdb = vod.searchResults.isNotEmpty;
    final hasAnime = vod.animeSearchResults.isNotEmpty;
    if (!hasTmdb && !hasAnime) {
      return Center(
        child: Text('Aucun résultat pour "${vod.searchQuery}"',
            style: AppTypography.body2.copyWith(color: AppColor.textMuted)),
      );
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
      children: [
        if (hasAnime) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text('ANIMÉS', style: AppTypography.caption.copyWith(
                color: AppColor.accentOrange, fontWeight: FontWeight.w700, letterSpacing: 1)),
          ),
          ...vod.animeSearchResults.map((a) => _buildAnimeSearchCard(a)),
        ],
        if (hasTmdb) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text('FILMS & SÉRIES', style: AppTypography.caption.copyWith(
                color: AppColor.primaryColor, fontWeight: FontWeight.w700, letterSpacing: 1)),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, childAspectRatio: 0.55, crossAxisSpacing: 8, mainAxisSpacing: 12,
            ),
            itemCount: vod.searchResults.length,
            itemBuilder: (context, index) => _buildMediaCard(vod.searchResults[index]),
          ),
        ],
      ],
    );
  }

  Widget _buildAnimeSearchCard(AnimeEntity anime) {
    return Card(
      color: AppColor.cardColor,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 50, height: 70,
            child: anime.imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: anime.imageUrl, fit: BoxFit.cover,
                    errorWidget: (_, _, _) => _miniPlaceholder(),
                  )
                : _miniPlaceholder(),
          ),
        ),
        title: Text(anime.title, style: AppTypography.body1.copyWith(color: AppColor.textPrimary)),
        subtitle: Text(anime.slug, style: AppTypography.caption.copyWith(color: AppColor.textMuted, fontSize: 11)),
        trailing: const Icon(Icons.play_circle_outline, color: AppColor.accentOrange, size: 28),
        onTap: () => _onAnimeTap(anime),
      ),
    );
  }

  Widget _miniPlaceholder() {
    return Container(
      color: AppColor.surfaceColor,
      child: const Icon(Icons.animation_outlined, color: AppColor.textMuted, size: 24),
    );
  }

  Widget _buildAnimeSection(VodProvider vod) {
    if (vod.selectedAnime != null) {
      return _buildAnimeEpisodes(vod);
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search, size: 48, color: AppColor.textMuted.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('Recherchez un animé',
              style: AppTypography.body1.copyWith(color: AppColor.textMuted)),
          const SizedBox(height: 8),
          Text('One Piece, Naruto, Attack on Titan...',
              style: AppTypography.caption.copyWith(color: AppColor.textMuted)),
        ],
      ),
    );
  }

  Widget _buildAnimeEpisodes(VodProvider vod) {
    final anime = vod.selectedAnime!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header anime
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColor.textPrimary),
                onPressed: () => vod.clearAnimeSelection(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(anime.title, style: AppTypography.heading3),
                    Text('${vod.animeEpisodes.length} épisodes',
                        style: AppTypography.caption
                            .copyWith(color: AppColor.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Chips langue
        if (vod.animeLangs.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: vod.animeLangs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final lang = vod.animeLangs[index];
                  final isSelected = lang == vod.selectedAnimeLang;
                  final label = lang.toUpperCase();
                  return ChoiceChip(
                    label: Text(label),
                    selected: isSelected,
                    onSelected: (_) => vod.setAnimeLang(lang),
                    backgroundColor: AppColor.cardColor,
                    selectedColor: AppColor.accentOrange,
                    labelStyle: AppTypography.caption.copyWith(
                      color: isSelected ? Colors.white : AppColor.textMuted,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w400,
                    ),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
          ),
        const SizedBox(height: 8),
        // Épisodes
        if (vod.isAnimeLoading)
          const Expanded(
              child: Center(
                  child: CircularProgressIndicator(
                      color: AppColor.primaryColor)))
        else if (vod.animeEpisodes.isEmpty)
          const Expanded(
              child: Center(
                  child: Text('Aucun épisode trouvé',
                      style: TextStyle(color: AppColor.textMuted))))
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: vod.animeEpisodes.length,
              itemBuilder: (context, index) {
                final ep = vod.animeEpisodes[index];
                return Card(
                  color: AppColor.cardColor,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color:
                            AppColor.accentOrange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text('${ep.number}',
                            style: AppTypography.body1.copyWith(
                                color: AppColor.accentOrange,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                    title: Text('Épisode ${ep.number}',
                        style: AppTypography.body1
                            .copyWith(color: AppColor.textPrimary)),
                    subtitle: Text(ep.provider.toUpperCase(),
                        style: AppTypography.caption.copyWith(
                            color: AppColor.textMuted, fontSize: 10)),
                    trailing: const Icon(Icons.play_arrow_rounded,
                        color: AppColor.accentOrange),
                    onTap: () => _playAnimeEpisode(context, vod, ep),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildContent(VodProvider vod) {
    final results = vod.filteredResults;
    if (results.isEmpty) {
      return Center(
        child: Text('Aucun contenu disponible',
            style: AppTypography.body2.copyWith(color: AppColor.textMuted)),
      );
    }
    return _buildMediaGrid(results);
  }

  Widget _buildMediaGrid(List<MediaEntity> items) {
    return Consumer<VodProvider>(
      builder: (context, vod, _) {
        final totalItems = items.length + (vod.isLoadingMore ? 3 : 0);
        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.55,
            crossAxisSpacing: 8,
            mainAxisSpacing: 12,
          ),
          itemCount: totalItems,
          itemBuilder: (context, index) {
            if (index >= items.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                      color: AppColor.primaryColor, strokeWidth: 2),
                ),
              );
            }
            return _buildMediaCard(items[index]);
          },
        );
      },
    );
  }

  Widget _buildMediaCard(MediaEntity media) {
    return GestureDetector(
      onTap: () => _onMediaTap(media),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColor.cardColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: media.fullPosterUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: media.fullPosterUrl, fit: BoxFit.cover,
                            placeholder: (_, _) => _posterPlaceholder(),
                            errorWidget: (_, _, _) => _posterPlaceholder(),
                          ),
                        )
                      : _posterPlaceholder(),
                ),
                Positioned(
                  top: 6, left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: media.isMovie
                          ? AppColor.primaryColor.withValues(alpha: 0.9)
                          : AppColor.accentOrange.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(media.isMovie ? 'FILM' : 'SÉRIE',
                        style: AppTypography.caption.copyWith(
                            color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700)),
                  ),
                ),
                if (media.voteAverage > 0)
                  Positioned(
                    top: 6, right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 10),
                          const SizedBox(width: 2),
                          Text(media.rating,
                              style: AppTypography.caption.copyWith(
                                  color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(media.title,
              style: AppTypography.caption.copyWith(
                  color: AppColor.textPrimary, fontWeight: FontWeight.w500, fontSize: 11),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          if (media.year.isNotEmpty)
            Text(media.year,
                style: AppTypography.caption.copyWith(color: AppColor.textMuted, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _posterPlaceholder() {
    return Container(
      decoration: BoxDecoration(color: AppColor.surfaceColor, borderRadius: BorderRadius.circular(10)),
      child: const Center(child: Icon(Icons.movie_outlined, size: 32, color: AppColor.textMuted)),
    );
  }

  void _onMediaTap(MediaEntity media) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColor.surfaceColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (_) => _MediaDetailSheet(media: media),
    );
  }

  void _onAnimeTap(AnimeEntity anime) {
    final vod = context.read<VodProvider>();
    vod.setCategory(VodCategory.anime);
    vod.loadAnimeEpisodes(anime);
  }

  Future<void> _playAnimeEpisode(
      BuildContext context, VodProvider vod, AnimeEpisode episode) async {
    debugPrint('[VOD] Playing anime episode ${episode.number} (${episode.provider})');

    final streamUrl = await vod.getAnimeStream(episode);
    if (!context.mounted) return;

    // If m3u8 extraction succeeded, play directly; otherwise fallback to WebView
    // which intercepts the m3u8 URL from VidMoly's JS player.
    if (streamUrl != null) {
      debugPrint('[VOD] ✅ Direct m3u8 found, playing directly');
    } else {
      debugPrint('[VOD] ⚠️ m3u8 extraction failed, falling back to WebView intercept');
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VodPlayerScreen(
          embedUrl: episode.embedUrl,
          directHlsUrl: streamUrl,
          title: '${vod.selectedAnime?.title ?? "Animé"} - Épisode ${episode.number}',
        ),
      ),
    );
  }
}

/// Bottom sheet détail d'un film/série.
class _MediaDetailSheet extends StatefulWidget {
  final MediaEntity media;
  const _MediaDetailSheet({required this.media});

  @override
  State<_MediaDetailSheet> createState() => _MediaDetailSheetState();
}

class _MediaDetailSheetState extends State<_MediaDetailSheet> {
  @override
  void initState() {
    super.initState();
    if (widget.media.isTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<VodProvider>().loadTvSeasons(widget.media);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColor.surfaceColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColor.textMuted,
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 20),
              if (media.fullBackdropUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 200,
                    width: double.infinity,
                    child: CachedNetworkImage(
                      imageUrl: media.fullBackdropUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Container(
                        color: AppColor.cardColor,
                        child: const Center(
                            child: Icon(Icons.movie,
                                color: AppColor.textMuted, size: 48)),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(media.title, style: AppTypography.heading2),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (media.year.isNotEmpty) ...[
                    Text(media.year,
                        style: AppTypography.body2
                            .copyWith(color: AppColor.textMuted)),
                    const SizedBox(width: 12),
                  ],
                  if (media.voteAverage > 0) ...[
                    const Icon(Icons.star, color: Colors.amber, size: 16),
                    const SizedBox(width: 4),
                    Text(media.rating,
                        style: AppTypography.body2.copyWith(
                            color: AppColor.textPrimary,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 12),
                  ],
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: media.isMovie
                          ? AppColor.primaryColor.withValues(alpha: 0.15)
                          : AppColor.accentOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(media.isMovie ? 'Film' : 'Série',
                        style: AppTypography.caption.copyWith(
                            color: media.isMovie
                                ? AppColor.primaryColor
                                : AppColor.accentOrange,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              if (media.genres.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: media.genres
                      .map((g) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: AppColor.cardColor,
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(g,
                                style: AppTypography.caption.copyWith(
                                    color: AppColor.textSecondary,
                                    fontSize: 11)),
                          ))
                      .toList(),
                ),
              ],
              if (media.overview.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Synopsis',
                    style:
                        AppTypography.body1.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(media.overview,
                    style: AppTypography.body2
                        .copyWith(color: AppColor.textSecondary, height: 1.5)),
              ],

              // --- Séries : onglets saisons + épisodes ---
              if (media.isTv) ...[
                const SizedBox(height: 20),
                _buildTvSection(media),
              ],

              const SizedBox(height: 24),
              // Bouton play principal
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _playMedia(context),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    media.isMovie
                        ? 'Regarder le film'
                        : 'Regarder S${context.read<VodProvider>().selectedTvSeason}:E1',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColor.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTvSection(MediaEntity media) {
    return Consumer<VodProvider>(
      builder: (context, vod, _) {
        if (vod.isTvLoading) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
                child: CircularProgressIndicator(
                    color: AppColor.primaryColor, strokeWidth: 2)),
          );
        }

        if (vod.tvSeasons.isEmpty) return const SizedBox.shrink();

        final progress = AppStorage.getWatchProgress(media.tmdbId);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Saisons & Épisodes',
                    style: AppTypography.body1
                        .copyWith(fontWeight: FontWeight.w600)),
                if (progress != null) ...[
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      final ep = TvEpisode(
                        seasonNumber: progress['season']!,
                        episodeNumber: progress['episode']!,
                      );
                      _playEpisode(ep);
                    },
                    icon: const Icon(Icons.play_circle_outline, size: 18),
                    label: Text(
                      'Reprendre S${progress['season']}:E${progress['episode']}',
                      style: AppTypography.caption.copyWith(
                          color: AppColor.primaryColor,
                          fontWeight: FontWeight.w600),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // Onglets saisons
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: vod.tvSeasons.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final season = vod.tvSeasons[index];
                  final isSelected =
                      vod.selectedTvSeason == season.seasonNumber;
                  final watched =
                      vod.countWatchedInSeason(media.tmdbId, season.seasonNumber);
                  final total = season.episodeCount;
                  final label = 'S${season.seasonNumber}'
                      '${watched > 0 ? ' ($watched/$total)' : ''}';
                  return ChoiceChip(
                    label: Text(label),
                    selected: isSelected,
                    onSelected: (_) {
                      vod.loadTvEpisodes(media,
                          season: season.seasonNumber);
                    },
                    backgroundColor: AppColor.cardColor,
                    selectedColor: AppColor.primaryColor,
                    labelStyle: AppTypography.caption.copyWith(
                      color: isSelected ? Colors.white : AppColor.textMuted,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w400,
                    ),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12),
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            // Liste des épisodes
            if (vod.tvEpisodes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('Aucun épisode disponible',
                    style: AppTypography.caption
                        .copyWith(color: AppColor.textMuted)),
              )
            else
              ...vod.tvEpisodes.map((ep) =>
                  _buildEpisodeCard(ep, media.tmdbId)),
          ],
        );
      },
    );
  }

  Widget _buildEpisodeCard(TvEpisode ep, int tmdbId) {
    final watched = AppStorage.getWatchedEpisodes(
            tmdbId, season: ep.seasonNumber)
        .contains(ep.episodeNumber);
    final progress = AppStorage.getWatchProgress(tmdbId);
    final isResumePoint = progress != null &&
        progress['season'] == ep.seasonNumber &&
        progress['episode'] == ep.episodeNumber;

    return Card(
      color: AppColor.cardColor,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: watched
                ? AppColor.primaryColor.withValues(alpha: 0.25)
                : AppColor.primaryColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: watched
                ? const Icon(Icons.check,
                    color: AppColor.primaryColor, size: 20)
                : Text('${ep.episodeNumber}',
                    style: AppTypography.body1.copyWith(
                        color: AppColor.primaryColor,
                        fontWeight: FontWeight.w700)),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(ep.title,
                  style: AppTypography.body1.copyWith(
                      color: AppColor.textPrimary, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            if (isResumePoint) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColor.accentOrange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('Reprendre',
                    style: AppTypography.caption.copyWith(
                        color: AppColor.accentOrange,
                        fontSize: 9,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
        subtitle: ep.overview.isNotEmpty
            ? Text(ep.overview,
                style: AppTypography.caption
                    .copyWith(color: AppColor.textMuted, fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis)
            : (ep.year.isNotEmpty
                ? Text(ep.year,
                    style: AppTypography.caption
                        .copyWith(color: AppColor.textMuted, fontSize: 11))
                : null),
        trailing: Icon(Icons.play_arrow_rounded,
            color: AppColor.primaryColor.withValues(alpha: 0.7)),
        onTap: () => _playEpisode(ep),
      ),
    );
  }

  Future<void> _playEpisode(TvEpisode ep) async {
    debugPrint('[VOD] Playing: ${widget.media.title} '
        'S${ep.seasonNumber}E${ep.episodeNumber}');

    final vod = context.read<VodProvider>();
    final stream = await vod.getStream(widget.media,
        season: ep.seasonNumber, episode: ep.episodeNumber);

    if (stream == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun stream disponible')),
        );
      }
      return;
    }

    // Sauvegarder la progression.
    AppStorage.saveWatchProgress(widget.media.tmdbId,
        season: ep.seasonNumber, episode: ep.episodeNumber);

    if (!context.mounted) return;
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VodPlayerScreen(
          embedUrl: stream.embedUrl,
          directHlsUrl: stream.directHlsUrl,
          title:
              '${widget.media.title} - S${ep.seasonNumber}E${ep.episodeNumber}',
          headers: stream.headers,
          tmdbId: widget.media.tmdbId,
          season: ep.seasonNumber,
          episode: ep.episodeNumber,
          totalEpisodesInSeason: vod.tvEpisodes.length,
          isTv: true,
        ),
      ),
    );
  }

  Future<void> _playMedia(BuildContext context) async {
    final media = widget.media;
    debugPrint('[VOD] Playing: ${media.title} (TMDB:${media.tmdbId})');

    final vod = context.read<VodProvider>();

    // Reprendre à la dernière position si available pour les séries.
    int season = vod.selectedTvSeason;
    int episode = 1;
    if (media.isTv) {
      final progress = AppStorage.getWatchProgress(media.tmdbId);
      if (progress != null) {
        season = progress['season']!;
        episode = progress['episode']!;
      }
    }

    final stream =
        await vod.getStream(media, season: season, episode: episode);

    if (stream == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun stream disponible')),
        );
      }
      return;
    }

    // Sauvegarder la progression.
    if (media.isTv) {
      AppStorage.saveWatchProgress(media.tmdbId,
          season: season, episode: episode);
    }

    if (!context.mounted) return;
    Navigator.of(context).pop();
    debugPrint(
        '[VOD] ✅ Opening ${stream.provider} (${stream.hasDirectHls ? "HLS" : "WebView"})');

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VodPlayerScreen(
          embedUrl: stream.embedUrl,
          directHlsUrl: stream.directHlsUrl,
          title: media.isMovie
              ? media.title
              : '${media.title} - S$season:E$episode',
          headers: stream.headers,
          tmdbId: media.tmdbId,
          season: season,
          episode: episode,
          totalEpisodesInSeason: vod.tvEpisodes.length,
          isTv: media.isTv,
        ),
      ),
    );
  }
}
