import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:walk_guide/services/firestore_service.dart';

import 'mocks/mocks.mocks.dart';

void main() {
  group('FirestoreService', () {
    late MockFirebaseAuth mockAuth;
    late MockFirebaseFirestore mockFirestore;
    late MockUser mockUser;
    late MockCollectionReference<Map<String, dynamic>> mockUserCollection;
    late MockCollectionReference<Map<String, dynamic>> mockSubCollection;
    late MockDocumentReference<Map<String, dynamic>> mockDocRef;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      mockFirestore = MockFirebaseFirestore();
      mockUser = MockUser();
      mockUserCollection = MockCollectionReference<Map<String, dynamic>>();
      mockSubCollection = MockCollectionReference<Map<String, dynamic>>();
      mockDocRef = MockDocumentReference<Map<String, dynamic>>();

      when(mockAuth.currentUser).thenReturn(mockUser);
      when(mockUser.uid).thenReturn('test_uid');
      when(mockFirestore.collection('users')).thenReturn(mockUserCollection);
      when(mockUserCollection.doc(any)).thenReturn(mockDocRef);
      when(mockDocRef.collection(any)).thenReturn(mockSubCollection);
      when(mockSubCollection.doc(any)).thenReturn(mockDocRef);
    });

    test('saveDailySteps should call set with correct data', () async {
      when(mockDocRef.set(any)).thenAnswer((_) async => null);

      await FirestoreService.saveDailySteps(3000);

      verify(mockDocRef.set(argThat(containsPair('steps', 3000)))).called(1);
    });

    test('saveWalkingSpeed should not save invalid speed', () async {
      await FirestoreService.saveWalkingSpeed(-1); // 유효하지 않은 속도
      verifyNever(mockSubCollection.add(any));
    });

    test('saveAggregateStats should call set if all fields exist', () async {
      final stats = {
        'daily_steps': 3000,
        'daily_avg_speed': 1.1,
        'weekly_steps': 12000,
        'weekly_avg_speed': 1.0,
      };

      when(mockDocRef.set(any)).thenAnswer((_) async => null);

      await FirestoreService.saveAggregateStats(stats);

      verify(mockDocRef.set(argThat(contains('daily_steps')))).called(1);
    });
  });
}
