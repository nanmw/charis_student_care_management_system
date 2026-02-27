import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/data/repositories/ministry_entry_repository.dart';
import 'package:charis_student_care/presentation/providers/facilitator_scope_provider.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';

final ministryEntryRepositoryProvider = Provider<MinistryEntryRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return MinistryEntryRepository(db);
});

/// Summary stats for ministry hours dashboard cards. Scoped by current user's classes when facilitator.
final ministrySummaryStatsProvider =
    StreamProvider.autoDispose<MinistrySummaryStats>((ref) {
  final repo = ref.watch(ministryEntryRepositoryProvider);
  final classIdsAsync = ref.watch(currentUserAssignedClassIdsProvider);
  return classIdsAsync.when(
    data: (classIds) => repo.watchMinistrySummaryStats(
      classIds: (classIds != null && classIds.isNotEmpty) ? classIds : null,
    ),
    loading: () => repo.watchMinistrySummaryStats(),
    error: (_, __) => repo.watchMinistrySummaryStats(),
  );
});

/// Page size for infinite scroll.
const int ministryEntriesPageSize = 25;

/// State for the ministry entries list (infinite scroll).
class MinistryEntriesState {
  const MinistryEntriesState({
    this.entries = const [],
    this.totalCount = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.filters = const MinistryEntryFilters(),
  });

  final List<MinistryEntryWithStudent> entries;
  final int totalCount;
  final bool isLoading;
  final bool isLoadingMore;
  final MinistryEntryFilters filters;

  MinistryEntriesState copyWith({
    List<MinistryEntryWithStudent>? entries,
    int? totalCount,
    bool? isLoading,
    bool? isLoadingMore,
    MinistryEntryFilters? filters,
  }) {
    return MinistryEntriesState(
      entries: entries ?? this.entries,
      totalCount: totalCount ?? this.totalCount,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      filters: filters ?? this.filters,
    );
  }
}

/// Notifier for ministry entries list with infinite scroll and filters.
class MinistryEntriesNotifier extends StateNotifier<MinistryEntriesState> {
  MinistryEntriesNotifier(this._ref, this._repo) : super(const MinistryEntriesState());

  final Ref _ref;
  final MinistryEntryRepository _repo;

  MinistryEntryFilters get _effectiveFilters {
    final classIds = _ref.read(currentUserAssignedClassIdsProvider).valueOrNull;
    final scopeClassIds =
        (classIds != null && classIds.isNotEmpty) ? classIds : null;
    return MinistryEntryFilters(
      search: state.filters.search,
      year: state.filters.year,
      ministryType: state.filters.ministryType,
      dateFrom: state.filters.dateFrom,
      dateTo: state.filters.dateTo,
      classIds: scopeClassIds,
    );
  }

  /// Load first page with current filters. Call when filters change or after add/edit.
  Future<void> loadInitial() async {
    state = state.copyWith(isLoading: true, entries: [], totalCount: 0);
    try {
      final filters = _effectiveFilters;
      final total =
          await _repo.getMinistryEntriesTotalCount(filters: filters);
      final list = await _repo.getMinistryEntriesPage(
        ministryEntriesPageSize,
        0,
        filters: filters,
      );
      state = state.copyWith(
        entries: list,
        totalCount: total,
        isLoading: false,
      );
    } catch (e, st) {
      state = state.copyWith(isLoading: false);
      throw StateError('Failed to load ministry entries: $e\n$st');
    }
  }

  /// Update filters and reload from the first page.
  Future<void> setFiltersAndReload(MinistryEntryFilters filters) async {
    state = state.copyWith(filters: filters);
    await loadInitial();
  }

  /// Load next page and append to list.
  Future<void> loadMore() async {
    if (state.isLoadingMore || state.entries.length >= state.totalCount) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final filters = _effectiveFilters;
      final offset = state.entries.length;
      final list = await _repo.getMinistryEntriesPage(
        ministryEntriesPageSize,
        offset,
        filters: filters,
      );
      state = state.copyWith(
        entries: [...state.entries, ...list],
        isLoadingMore: false,
      );
    } catch (e, st) {
      state = state.copyWith(isLoadingMore: false);
      throw StateError('Failed to load more ministry entries: $e\n$st');
    }
  }
}

final ministryEntriesProvider =
    StateNotifierProvider.autoDispose<MinistryEntriesNotifier, MinistryEntriesState>(
        (ref) {
  final repo = ref.watch(ministryEntryRepositoryProvider);
  return MinistryEntriesNotifier(ref, repo);
});

/// Selected class id and study mode for the ministry hours summary view (e.g. class 1 = Year 1, "Full-time").
const int defaultMinistrySummaryClassId = 1;
const String defaultMinistrySummaryStudyMode = 'Full-time';

final ministrySummaryClassIdProvider =
    StateProvider.autoDispose<int>((ref) => defaultMinistrySummaryClassId);
final ministrySummaryStudyModeProvider =
    StateProvider.autoDispose<String>((ref) => defaultMinistrySummaryStudyMode);

/// Reactive list of ministry hours summary rows for the given class and study mode.
final ministryHoursSummaryProvider = StreamProvider.autoDispose
    .family<List<MinistryHoursSummaryRow>, (int, String)>((ref, key) {
  final repo = ref.watch(ministryEntryRepositoryProvider);
  final (classId, studyMode) = key;
  return repo.watchMinistryHoursSummary(classId, studyMode);
});
