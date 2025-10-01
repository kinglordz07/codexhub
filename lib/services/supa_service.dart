import 'package:supabase_flutter/supabase_flutter.dart';
import '../collabscreen/model.dart';

class SupabaseService {
  final supabase = Supabase.instance.client;

  /// Add new collaborator
  Future<void> addCollaborator(Room room) async {
    try {
      await supabase.from('room').insert(room.toJson());
    } catch (e) {
      throw Exception("Failed to add room: $e");
    }
  }

  /// Get all collaborators
  Future<List<Room>> getCollaborators() async {
    try {
      final response = await supabase.from('room').select();

      // response is a List<dynamic>
      final data = response as List<dynamic>;

      return data
          .map((json) => Room.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception("Failed to fetch collaborators: $e");
    }
  }

  /// Delete collaborator
  Future<void> deleteCollaborator(String id) async {
    try {
      await supabase.from('collaborators').delete().eq('id', id);
    } catch (e) {
      throw Exception("Failed to delete collaborator: $e");
    }
  }
}
