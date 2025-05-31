import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  static Future<void> saveWalkingSpeed(double speed) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final timestamp = Timestamp.now();

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('walking_data')
        .add({
          'speed': speed,
          'timestamp': timestamp,
        });
  }
}
