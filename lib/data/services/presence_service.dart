import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/constant.dart';
import '../models/user_model.dart';

// Firestore presence: write online status + listen to users collection
class PresenceService {
  PresenceService({FirebaseFirestore? firestore})
      : _injectedFirestore = firestore;

  final FirebaseFirestore? _injectedFirestore;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  Stream<List<UserModel>> watchUsers() {
    return _firestore
        .collection(AppConstants.usersCollection)
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          final now = DateTime.now();
          return snapshot.docs
              .map((doc) => UserModel.fromFirestore(doc.data(), doc.id))
              // If app was killed, heartbeat stops; drop stale users automatically.
              .where((user) {
                final seenAt = user.lastSeen;
                if (seenAt == null) return false;
                final ageSeconds = now.difference(seenAt.toLocal()).inSeconds;
                return ageSeconds <= AppConstants.presenceStaleSeconds;
              })
              .toList();
        });
  }

  Future<void> setOnline({
    required String deviceId,
    required String name,
  }) async {
    await _firestore.collection(AppConstants.usersCollection).doc(deviceId).set(
      {
        'name': name,
        'deviceId': deviceId,
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // Fetch single user doc for pre-call offline check
  Future<UserModel?> getUser(String deviceId) async {
    final doc = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(deviceId)
        .get();
    if (!doc.exists || doc.data() == null) return null;
    return UserModel.fromFirestore(doc.data()!, doc.id);
  }

  // True when user is online and heartbeat is fresh
  static bool isUserCurrentlyOnline(UserModel user) {
    if (!user.isOnline) return false;
    final seenAt = user.lastSeen;
    if (seenAt == null) return false;
    final ageSeconds = DateTime.now().difference(seenAt.toLocal()).inSeconds;
    return ageSeconds <= AppConstants.presenceStaleSeconds;
  }

  Future<void> setOffline({required String deviceId}) async {
    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(deviceId)
        .set(
          {
            'isOnline': false,
            'lastSeen': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
  }
}
