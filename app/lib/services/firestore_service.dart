import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  static Future<void> saveDailySteps(int stepCount) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final now = DateTime.now();
    final dateKey =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('daily_steps')
        .doc(dateKey);

    await docRef.set({
      'steps': stepCount,
      'date': Timestamp.fromDate(now),
    });
  }

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
