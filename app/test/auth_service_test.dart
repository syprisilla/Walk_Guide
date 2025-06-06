import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:walk_guide/services/auth_service_testable.dart';
import 'mocks/mocks.mocks.dart';

void main() {
  group('AuthService Unit Test', () {
    late MockFirebaseAuth mockAuth;
    late MockGoogleSignIn mockGoogleSignIn;
    late AuthService authService;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      mockGoogleSignIn = MockGoogleSignIn();
      authService = AuthService(
        auth: mockAuth,
        googleSignIn: mockGoogleSignIn,
      );
    });

    test('signInWithEmail returns user on success', () async {
      final mockCredential = MockUserCredential();
      final mockUser = MockUser();

      when(mockCredential.user).thenReturn(mockUser);
      when(mockAuth.signInWithEmailAndPassword(
        email: anyNamed('email'),
        password: anyNamed('password'),
      )).thenAnswer((_) async => mockCredential);

      final result = await authService.signInWithEmail(
        'test@example.com',
        'password123',
      );

      expect(result, mockUser);
    });

    test('signInWithEmail returns null on FirebaseAuthException', () async {
      when(mockAuth.signInWithEmailAndPassword(
        email: anyNamed('email'),
        password: anyNamed('password'),
      )).thenThrow(FirebaseAuthException(code: 'user-not-found'));

      final result = await authService.signInWithEmail(
        'fail@example.com',
        'wrongpass',
      );

      expect(result, isNull);
    });

    test('signOut calls signOut on both FirebaseAuth and GoogleSignIn',
        () async {
      when(mockAuth.signOut()).thenAnswer((_) async {});
      when(mockGoogleSignIn.disconnect()).thenAnswer((_) async {});
      when(mockGoogleSignIn.signOut()).thenAnswer((_) async {});

      await authService.signOut();

      verify(mockAuth.signOut()).called(1);
      verify(mockGoogleSignIn.signOut()).called(1);
    });
  });
}
