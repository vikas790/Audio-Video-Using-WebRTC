import '../models/user_model.dart';
import '../services/presence_service.dart';
import 'base_repository.dart';

// Presence data access layer
class PresenceRepository extends BaseRepository {
  PresenceRepository(this._service);

  final PresenceService _service;

  Stream<List<UserModel>> watchUsers() => _service.watchUsers();

  Future<UserModel?> getUser(String deviceId) => _service.getUser(deviceId);

  bool isUserCurrentlyOnline(UserModel user) =>
      PresenceService.isUserCurrentlyOnline(user);

  Future<void> setOnline({
    required String deviceId,
    required String name,
  }) =>
      _service.setOnline(deviceId: deviceId, name: name);

  Future<void> setOffline({required String deviceId}) =>
      _service.setOffline(deviceId: deviceId);
}
