import 'package:mockito/annotations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

@GenerateMocks([
  // Firebase Auth 관련
  FirebaseAuth,
  UserCredential,
  User,

  // Google 로그인 관련
  GoogleSignIn,
  GoogleSignInAccount,
  GoogleSignInAuthentication,

  // Firestore 관련 (제네릭 명시 필수)
  FirebaseFirestore,
  CollectionReference<Map<String, dynamic>>,
  DocumentReference<Map<String, dynamic>>,
  DocumentSnapshot<Map<String, dynamic>>,
  QuerySnapshot<Map<String, dynamic>>,
  Query<Map<String, dynamic>>,
])
void main() {}
