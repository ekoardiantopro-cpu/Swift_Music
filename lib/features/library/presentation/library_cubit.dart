import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/library_repository.dart';

class LibraryState {
  LibraryState({
    Set<String> likes = const {},
    List<String> recent = const [],
    this.error,
  }) : likes = Set.unmodifiable(likes),
       recent = List.unmodifiable(recent);
  final Set<String> likes;
  final List<String> recent;
  final String? error;
}

class LibraryCubit extends Cubit<LibraryState> {
  LibraryCubit(this._repository) : super(LibraryState());
  final LibraryRepository _repository;
  Future<void> mergeLikes(Set<String> incoming) async {
    final likes = {...state.likes, ...incoming};
    await _repository.saveLikes(likes);
    if (!isClosed) emit(LibraryState(likes: likes, recent: state.recent));
  }

  Future<void> removeTrack(String id) async {
    final likes = {...state.likes}..remove(id);
    final recent = state.recent.where((track) => track != id).toList();
    emit(LibraryState(likes: likes, recent: recent));
    try {
      await _repository.saveLikes(likes);
      await _repository.saveRecent(recent);
    } catch (_) {
      if (!isClosed) {
        emit(
          LibraryState(
            likes: state.likes,
            recent: state.recent,
            error: 'Perubahan Library belum tersimpan.',
          ),
        );
      }
    }
  }

  Future<void> initialize() async {
    try {
      final likes = await _repository.loadLikes();
      final recent = await _repository.loadRecent();
      if (!isClosed) emit(LibraryState(likes: likes, recent: recent));
    } catch (_) {
      if (!isClosed) {
        emit(LibraryState(error: 'Penyimpanan lokal tidak tersedia.'));
      }
    }
  }

  Future<void> toggleLike(String id) async {
    final likes = {...state.likes};
    likes.contains(id) ? likes.remove(id) : likes.add(id);
    emit(LibraryState(likes: likes, recent: state.recent));
    try {
      await _repository.saveLikes(likes);
    } catch (_) {
      if (!isClosed) {
        emit(
          LibraryState(
            likes: state.likes,
            recent: state.recent,
            error: 'Favorit belum tersimpan ke perangkat.',
          ),
        );
      }
    }
  }

  Future<void> recordPlay(String id) async {
    if (state.recent.isNotEmpty && state.recent.first == id) return;
    final recent = [
      id,
      ...state.recent.where((item) => item != id),
    ].take(6).toList();
    emit(LibraryState(likes: state.likes, recent: recent));
    try {
      await _repository.saveRecent(recent);
    } catch (_) {
      if (!isClosed) {
        emit(
          LibraryState(
            likes: state.likes,
            recent: state.recent,
            error: 'Riwayat belum tersimpan ke perangkat.',
          ),
        );
      }
    }
  }
}
