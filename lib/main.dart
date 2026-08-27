import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_service.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  runApp(const BorewellGuardApp());
}

// ============================================================
// APP
// ============================================================

class BorewellGuardApp extends StatelessWidget {
  const BorewellGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Borewell Guard',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1687E8),
          brightness: Brightness.dark,
        ),
      ),
      home: const LoginPage(),
    );
  }
}

// ============================================================
// USER DATA
// ============================================================

class UserData {
  static String firstName = '';
  static String lastName = '';
  static String mobile = '';
  static String email = '';

  static bool registered = false;

  static String get fullName {
    final name = '$firstName $lastName'.trim();

    if (name.isEmpty) {
      return 'Borewell Owner';
    }

    return name;
  }

  static void clear() {
    firstName = '';
    lastName = '';
    mobile = '';
    email = '';
    registered = false;
  }
}

// ============================================================
// LOGIN PAGE
// ============================================================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool hidePassword = true;
  bool loading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // ==========================================================
  // LOGIN
  // ==========================================================

  Future<void> login() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      showMessage('Please enter email and password.', Colors.orange);
      return;
    }

    setState(() {
      loading = true;
    });

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = credential.user;

      if (user == null) {
        throw Exception('Unable to login.');
      }

      await user.reload();

      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        throw Exception('Unable to load user.');
      }

      // ------------------------------------------------------
      // EMAIL VERIFICATION CHECK
      // ------------------------------------------------------

      if (!currentUser.emailVerified) {
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;

        await showDialog(
          context: context,
          builder: (_) {
            return AlertDialog(
              icon: const Icon(
                Icons.mark_email_unread,
                size: 60,
                color: Colors.orangeAccent,
              ),
              title: const Text('Email Not Verified'),
              content: Text(
                'Please verify your email address first.\n\n'
                'Verification email was sent to:\n${emailController.text.trim()}',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );

        return;
      }

      final uid = currentUser.uid;

      // ------------------------------------------------------
      // LOAD OWNER DATA
      // ------------------------------------------------------

      final snapshot = await FirebaseDatabase.instance.ref('owners/$uid').get();

      if (snapshot.exists && snapshot.value is Map) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);

        UserData.firstName = '${data['firstName'] ?? ''}';
        UserData.lastName = '${data['lastName'] ?? ''}';
        UserData.mobile = '${data['mobile'] ?? ''}';
        UserData.email = '${data['email'] ?? email}';
        UserData.registered = true;
      } else {
        UserData.email = email;
        UserData.registered = true;
      }

      // ------------------------------------------------------
      // FCM SETUP
      // ------------------------------------------------------

      await NotificationService.initialize();

      await NotificationService.saveToken(uid);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainApp()),
      );
    } on FirebaseAuthException catch (e) {
      String message;

      switch (e.code) {
        case 'user-not-found':
          message = 'No account found with this email.';
          break;

        case 'wrong-password':
        case 'invalid-credential':
          message = 'Incorrect email or password.';
          break;

        case 'invalid-email':
          message = 'Invalid email address.';
          break;

        case 'too-many-requests':
          message = 'Too many attempts. Please try again later.';
          break;

        case 'user-disabled':
          message = 'This account has been disabled.';
          break;

        default:
          message = e.message ?? 'Login failed.';
      }

      showMessage(message, Colors.redAccent);
    } catch (e) {
      showMessage('Something went wrong: $e', Colors.redAccent);
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  // ==========================================================
  // FORGOT PASSWORD
  // ==========================================================

  Future<void> forgotPassword() async {
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Forgot Password'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Registered Email',
              prefixIcon: Icon(Icons.email),
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                final email = controller.text.trim();

                if (email.isEmpty) {
                  showMessage('Please enter your email.', Colors.orange);
                  return;
                }

                try {
                  await FirebaseAuth.instance.sendPasswordResetEmail(
                    email: email,
                  );

                  if (!mounted) return;

                  Navigator.pop(context);

                  showMessage(
                    'Password reset email sent to $email',
                    Colors.green,
                  );
                } on FirebaseAuthException catch (e) {
                  showMessage(
                    e.message ?? 'Could not send reset email.',
                    Colors.redAccent,
                  );
                }
              },
              child: const Text('SEND'),
            ),
          ],
        );
      },
    );

    controller.dispose();
  }

  // ==========================================================
  // SIGNUP
  // ==========================================================

  void openSignup() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SignupPage()),
    );
  }

  // ==========================================================
  // MESSAGE
  // ==========================================================

  void showMessage(String message, Color color) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF031A38), Color(0xFF0759A8), Color(0xFF0A8FD8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 450),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF071D38),
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 25),
                ],
              ),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 42,
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.security, size: 48, color: Colors.white),
                  ),

                  const SizedBox(height: 18),

                  const Text(
                    'BOREWELL GUARD',
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),

                  const SizedBox(height: 6),

                  const Text(
                    'SMART SAFETY • SAVES LIVES',
                    style: TextStyle(
                      color: Colors.lightGreenAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 35),

                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Registered Email',
                      prefixIcon: const Icon(Icons.email),
                      filled: true,
                      fillColor: Colors.white.withOpacity(.07),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  TextField(
                    controller: passwordController,
                    obscureText: hidePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            hidePassword = !hidePassword;
                          });
                        },
                        icon: Icon(
                          hidePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(.07),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: forgotPassword,
                      child: const Text(
                        'Forgot Password?',
                        style: TextStyle(color: Colors.lightBlueAccent),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: loading ? null : login,
                      icon: loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: Text(
                        loading ? 'LOGGING IN...' : 'LOGIN',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 15),

                  TextButton(
                    onPressed: openSignup,
                    child: const Text(
                      "Don't have an account? SIGN UP",
                      style: TextStyle(
                        color: Colors.lightGreenAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SIGNUP PAGE
// ============================================================

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final mobileController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool hidePassword = true;
  bool hideConfirmPassword = true;
  bool loading = false;

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    mobileController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  // ==========================================================
  // SIGNUP
  // ==========================================================

  Future<void> signup() async {
    final firstName = firstNameController.text.trim();
    final lastName = lastNameController.text.trim();
    final mobile = mobileController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;
    final confirmPassword = confirmPasswordController.text;

    if (firstName.isEmpty ||
        mobile.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      showMessage('Please fill all required fields.', Colors.orange);
      return;
    }

    if (!email.contains('@') || !email.contains('.')) {
      showMessage('Please enter a valid email address.', Colors.redAccent);
      return;
    }

    if (mobile.length < 10) {
      showMessage('Please enter a valid mobile number.', Colors.redAccent);
      return;
    }

    if (password.length < 6) {
      showMessage(
        'Password must contain at least 6 characters.',
        Colors.redAccent,
      );
      return;
    }

    if (password != confirmPassword) {
      showMessage('Passwords do not match.', Colors.redAccent);
      return;
    }

    setState(() {
      loading = true;
    });

    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final user = credential.user;

      if (user == null) {
        throw Exception('Account creation failed.');
      }

      await user.updateDisplayName('$firstName $lastName'.trim());

      // ------------------------------------------------------
      // SEND EMAIL VERIFICATION
      // ------------------------------------------------------

      await user.sendEmailVerification();

      // ------------------------------------------------------
      // SAVE OWNER DATA
      // ------------------------------------------------------

      await FirebaseDatabase.instance.ref('owners/${user.uid}').set({
        'firstName': firstName,
        'lastName': lastName,
        'mobile': mobile,
        'email': email,
        'emailVerified': false,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });

      UserData.firstName = firstName;
      UserData.lastName = lastName;
      UserData.mobile = mobile;
      UserData.email = email;
      UserData.registered = true;

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) {
          return AlertDialog(
            icon: const Icon(
              Icons.mark_email_unread,
              size: 65,
              color: Colors.lightBlueAccent,
            ),
            title: const Text('Verify Your Email'),
            content: Text(
              'Account created successfully!\n\n'
              'A verification email has been sent to:\n\n'
              '$email\n\n'
              'Please open your email and click the verification link before logging in.',
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  try {
                    await user.sendEmailVerification();

                    if (mounted) {
                      showMessage(
                        'Verification email sent again.',
                        Colors.green,
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      showMessage('Could not resend email.', Colors.redAccent);
                    }
                  }
                },
                child: const Text('RESEND'),
              ),
              ElevatedButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();

                  if (!mounted) return;

                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                child: const Text('GO TO LOGIN'),
              ),
            ],
          );
        },
      );
    } on FirebaseAuthException catch (e) {
      String message;

      switch (e.code) {
        case 'email-already-in-use':
          message = 'This email is already registered.';
          break;

        case 'weak-password':
          message = 'Password is too weak.';
          break;

        case 'invalid-email':
          message = 'Invalid email address.';
          break;

        case 'operation-not-allowed':
          message = 'Email/password authentication is disabled.';
          break;

        default:
          message = e.message ?? 'Registration failed.';
      }

      showMessage(message, Colors.redAccent);
    } catch (e) {
      showMessage('Something went wrong: $e', Colors.redAccent);
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  // ==========================================================
  // MESSAGE
  // ==========================================================

  void showMessage(String message, Color color) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ==========================================================
  // FIELD
  // ==========================================================

  Widget field(
    String label,
    IconData icon,
    TextEditingController controller, {
    bool password = false,
    bool hide = true,
    VoidCallback? toggle,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        obscureText: password && hide,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: password
              ? IconButton(
                  onPressed: toggle,
                  icon: Icon(hide ? Icons.visibility : Icons.visibility_off),
                )
              : null,
          filled: true,
          fillColor: Colors.white.withOpacity(.06),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 550),
            child: Column(
              children: [
                const SizedBox(height: 10),

                const Icon(
                  Icons.person_add,
                  size: 70,
                  color: Colors.lightBlueAccent,
                ),

                const SizedBox(height: 12),

                const Text(
                  'CREATE YOUR ACCOUNT',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 25),

                field('First Name *', Icons.person, firstNameController),

                field('Last Name', Icons.person_outline, lastNameController),

                field(
                  'Mobile Number *',
                  Icons.phone,
                  mobileController,
                  keyboardType: TextInputType.phone,
                ),

                field(
                  'Email *',
                  Icons.email,
                  emailController,
                  keyboardType: TextInputType.emailAddress,
                ),

                field(
                  'Password *',
                  Icons.lock,
                  passwordController,
                  password: true,
                  hide: hidePassword,
                  toggle: () {
                    setState(() {
                      hidePassword = !hidePassword;
                    });
                  },
                ),

                field(
                  'Confirm Password *',
                  Icons.lock_outline,
                  confirmPasswordController,
                  password: true,
                  hide: hideConfirmPassword,
                  toggle: () {
                    setState(() {
                      hideConfirmPassword = !hideConfirmPassword;
                    });
                  },
                ),

                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  height: 53,
                  child: ElevatedButton.icon(
                    onPressed: loading ? null : signup,
                    icon: loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_add),
                    label: Text(
                      loading ? 'CREATING ACCOUNT...' : 'CREATE ACCOUNT',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// NOTIFICATION SERVICE
// ============================================================

class NotificationService {
  static StreamSubscription<RemoteMessage>? foregroundSubscription;

  static Future<void> initialize() async {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    // --------------------------------------------------------
    // FOREGROUND NOTIFICATION
    // --------------------------------------------------------

    foregroundSubscription ??= FirebaseMessaging.onMessage.listen((
      RemoteMessage message,
    ) {
      playNotificationSound();

      debugPrint('Notification received: ${message.notification?.title}');
    });

    // --------------------------------------------------------
    // TOKEN REFRESH
    // --------------------------------------------------------

    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        await FirebaseDatabase.instance
            .ref('owners/${user.uid}/fcmToken')
            .set(token);
      }
    });
  }

  static Future<void> saveToken(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();

      if (token != null) {
        await FirebaseDatabase.instance.ref('owners/$uid/fcmToken').set(token);
      }
    } catch (e) {
      debugPrint('FCM token error: $e');
    }
  }

  static void playNotificationSound() {
    SystemSound.play(SystemSoundType.alert);
  }

  static Future<void> dispose() async {
    await foregroundSubscription?.cancel();
    foregroundSubscription = null;
  }
}

// ============================================================
// MAIN APP
// ============================================================

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final DatabaseReference sensorRef = FirebaseDatabase.instance.ref(
    'borewell_guard/sensor',
  );

  final DatabaseReference settingsRef = FirebaseDatabase.instance.ref(
    'borewell_guard/settings',
  );

  int selectedIndex = 0;

  double dangerDistance = 2.0;
  double currentDistance = 4.0;

  bool personDetected = false;
  bool alarmOn = false;
  bool ownerNotified = false;

  Timer? alarmTimer;

  StreamSubscription<DatabaseEvent>? sensorSubscription;

  final List<AlertItem> alerts = [];

  bool get danger {
    return personDetected && currentDistance <= dangerDistance;
  }

  @override
  void initState() {
    super.initState();

    initializeSystem();
  }

  // ==========================================================
  // INITIALIZE SYSTEM
  // ==========================================================

  Future<void> initializeSystem() async {
    await NotificationService.initialize();

    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      await NotificationService.saveToken(user.uid);
    }

    await settingsRef.update({'dangerDistance': dangerDistance});

    sensorSubscription = sensorRef.onValue.listen(handleSensorData);
  }

  // ==========================================================
  // FIREBASE SENSOR DATA
  // ==========================================================

  void handleSensorData(DatabaseEvent event) {
    final data = event.snapshot.value;

    if (data is! Map) {
      return;
    }

    final distance = double.tryParse('${data['distance']}') ?? currentDistance;

    final humanDetected = data['humanDetected'] == true;

    if (!mounted) return;

    final previousDanger = danger;

    setState(() {
      currentDistance = distance;
      personDetected = humanDetected;

      if (personDetected && currentDistance <= dangerDistance) {
        alarmOn = true;
        ownerNotified = true;
      } else {
        alarmOn = false;
        ownerNotified = false;
        stopAlarm();
      }
    });

    final newDanger = personDetected && currentDistance <= dangerDistance;

    if (newDanger) {
      playAlarm();

      if (!previousDanger) {
        addDangerAlert();
        showDangerSnackBar();
      }
    }
  }

  // ==========================================================
  // ADD ALERT
  // ==========================================================

  void addDangerAlert() {
    alerts.insert(
      0,
      AlertItem(
        title: 'HUMAN DETECTED',
        message:
            'Person detected at '
            '${currentDistance.toStringAsFixed(1)} m. '
            'Danger zone entered.',
        time: TimeOfDay.now().format(context),
        type: 'CRITICAL',
      ),
    );
  }

  // ==========================================================
  // ALARM
  // ==========================================================

  void playAlarm() {
    if (alarmTimer != null) {
      return;
    }

    SystemSound.play(SystemSoundType.alert);

    alarmTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !alarmOn) {
        timer.cancel();
        alarmTimer = null;
        return;
      }

      SystemSound.play(SystemSoundType.alert);
    });
  }

  void stopAlarm() {
    alarmTimer?.cancel();
    alarmTimer = null;
  }

  // ==========================================================
  // DANGER SNACKBAR
  // ==========================================================

  void showDangerSnackBar() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🚨 DANGER! Human detected near borewell!'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 5),
      ),
    );
  }

  // ==========================================================
  // SIMULATE DETECTION
  // ==========================================================

  Future<void> simulateDetection() async {
    final distance = dangerDistance - 0.2;

    final safeDistance = distance < 0.5 ? 0.5 : distance;

    setState(() {
      personDetected = true;
      currentDistance = safeDistance;
      alarmOn = true;
      ownerNotified = true;

      alerts.insert(
        0,
        AlertItem(
          title: 'HUMAN DETECTED',
          message:
              'Person detected at '
              '${safeDistance.toStringAsFixed(1)} m. '
              'Danger zone entered.',
          time: TimeOfDay.now().format(context),
          type: 'CRITICAL',
        ),
      );
    });

    await sensorRef.set({
      'distance': safeDistance,
      'humanDetected': true,
      'alarmOn': true,
      'ownerNotified': true,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    playAlarm();

    showAlarmDialog();
  }

  // ==========================================================
  // CLEAR DETECTION
  // ==========================================================

  Future<void> clearDetection() async {
    stopAlarm();

    double safeDistance = dangerDistance + 1;

    if (safeDistance > 5) {
      safeDistance = 5;
    }

    setState(() {
      personDetected = false;
      alarmOn = false;
      ownerNotified = false;
      currentDistance = safeDistance;
    });

    await sensorRef.set({
      'distance': safeDistance,
      'humanDetected': false,
      'alarmOn': false,
      'ownerNotified': false,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Detection cleared. System is SAFE.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // ==========================================================
  // UPDATE CURRENT DISTANCE
  // ==========================================================

  Future<void> updateCurrentDistance(double value) async {
    bool newAlarm = false;
    bool newNotification = false;

    setState(() {
      currentDistance = value;

      if (personDetected && currentDistance <= dangerDistance) {
        newAlarm = true;
        newNotification = true;
        alarmOn = true;
        ownerNotified = true;
      } else {
        alarmOn = false;
        ownerNotified = false;
        stopAlarm();
      }
    });

    await sensorRef.update({
      'distance': currentDistance,
      'humanDetected': personDetected,
      'alarmOn': newAlarm,
      'ownerNotified': newNotification,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    if (newAlarm) {
      playAlarm();
    }
  }

  // ==========================================================
  // UPDATE DANGER DISTANCE
  // ==========================================================

  Future<void> updateDangerDistance(double value) async {
    setState(() {
      dangerDistance = value;

      if (personDetected) {
        if (currentDistance <= dangerDistance) {
          alarmOn = true;
          ownerNotified = true;
        } else {
          alarmOn = false;
          ownerNotified = false;
          stopAlarm();
        }
      }
    });

    await settingsRef.update({'dangerDistance': dangerDistance});

    if (personDetected && currentDistance <= dangerDistance) {
      playAlarm();
    }
  }

  // ==========================================================
  // ALARM DIALOG
  // ==========================================================

  void showAlarmDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF420000),
          icon: const Icon(
            Icons.warning_amber,
            color: Colors.redAccent,
            size: 70,
          ),
          title: const Text(
            'DANGER ALERT',
            style: TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Human detected!\n\n'
            'Distance: '
            '${currentDistance.toStringAsFixed(1)} m\n'
            'Danger Zone: '
            '${dangerDistance.toStringAsFixed(1)} m\n\n'
            'WARNING ALARM ACTIVE',
            textAlign: TextAlign.center,
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('OK - ACKNOWLEDGE'),
              ),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================
  // HOW TO USE
  // ==========================================================

  void showHowToUse() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF071D38),
      builder: (_) => const HowToUsePage(),
    );
  }

  // ==========================================================
  // LOGOUT
  // ==========================================================

  Future<void> logout() async {
    stopAlarm();

    await NotificationService.dispose();

    await FirebaseAuth.instance.signOut();

    UserData.clear();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    alarmTimer?.cancel();
    sensorSubscription?.cancel();
    super.dispose();
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(
        dangerDistance: dangerDistance,
        currentDistance: currentDistance,
        personDetected: personDetected,
        alarmOn: alarmOn,
        ownerNotified: ownerNotified,
        onMonitor: () {
          setState(() {
            selectedIndex = 1;
          });
        },
        onAlerts: () {
          setState(() {
            selectedIndex = 2;
          });
        },
      ),

      LiveMonitorPage(
        dangerDistance: dangerDistance,
        currentDistance: currentDistance,
        personDetected: personDetected,
        danger: danger,
        alarmOn: alarmOn,
        ownerNotified: ownerNotified,
        onDangerChanged: updateDangerDistance,
        onCurrentChanged: updateCurrentDistance,
        onSimulate: simulateDetection,
        onClear: clearDetection,
      ),

      AlertsPage(alerts: alerts),

      const SafetyGuidePage(),

      ProfilePage(onLogout: logout),
    ];

    return Scaffold(
      body: SafeArea(child: pages[selectedIndex]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: showHowToUse,
        icon: const Icon(Icons.help_outline),
        label: const Text('How to Use'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_outlined),
            selectedIcon: Icon(Icons.monitor),
            label: 'Live Monitor',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Guide',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DASHBOARD
// ============================================================

class DashboardPage extends StatelessWidget {
  final double dangerDistance;
  final double currentDistance;
  final bool personDetected;
  final bool alarmOn;
  final bool ownerNotified;

  final VoidCallback onMonitor;
  final VoidCallback onAlerts;

  const DashboardPage({
    super.key,
    required this.dangerDistance,
    required this.currentDistance,
    required this.personDetected,
    required this.alarmOn,
    required this.ownerNotified,
    required this.onMonitor,
    required this.onAlerts,
  });

  @override
  Widget build(BuildContext context) {
    final danger = personDetected && currentDistance <= dangerDistance;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 25,
                backgroundColor: Colors.blue,
                child: Icon(Icons.security),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Borewell Guard',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Smart Safety System',
                      style: TextStyle(color: Colors.lightGreenAccent),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onAlerts,
                icon: const Icon(Icons.notifications, size: 28),
              ),
            ],
          ),

          const SizedBox(height: 20),

          StatusCard(safe: !danger, personDetected: personDetected),

          const SizedBox(height: 18),

          Row(
            children: [
              Expanded(
                child: InfoCard(
                  title: 'Danger Zone',
                  value: '${dangerDistance.toStringAsFixed(1)} m',
                  icon: Icons.radar,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InfoCard(
                  title: 'Current Distance',
                  value: '${currentDistance.toStringAsFixed(1)} m',
                  icon: Icons.social_distance,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.06),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Live Sensor Status',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 15),

                sensor(
                  Icons.sensors,
                  'Distance Sensor',
                  '${currentDistance.toStringAsFixed(1)} m',
                  Colors.cyanAccent,
                ),

                sensor(
                  Icons.person,
                  'Human Detection',
                  personDetected ? 'HUMAN DETECTED' : 'NO PERSON DETECTED',
                  personDetected ? Colors.redAccent : Colors.lightGreenAccent,
                ),

                sensor(
                  Icons.alarm,
                  'Warning Alarm',
                  alarmOn ? 'ACTIVE' : 'OFF',
                  alarmOn ? Colors.redAccent : Colors.lightGreenAccent,
                ),

                sensor(
                  Icons.phone_android,
                  'Owner Notification',
                  ownerNotified ? 'SENT' : 'NONE',
                  ownerNotified ? Colors.orangeAccent : Colors.white54,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: onMonitor,
              icon: const Icon(Icons.monitor),
              label: const Text(
                'OPEN LIVE MONITOR',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),

          const SizedBox(height: 90),
        ],
      ),
    );
  }

  Widget sensor(IconData icon, String title, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(title)),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// LIVE MONITOR
// ============================================================

class LiveMonitorPage extends StatelessWidget {
  final double dangerDistance;
  final double currentDistance;
  final bool personDetected;
  final bool danger;
  final bool alarmOn;
  final bool ownerNotified;

  final ValueChanged<double> onDangerChanged;
  final ValueChanged<double> onCurrentChanged;

  final VoidCallback onSimulate;
  final VoidCallback onClear;

  const LiveMonitorPage({
    super.key,
    required this.dangerDistance,
    required this.currentDistance,
    required this.personDetected,
    required this.danger,
    required this.alarmOn,
    required this.ownerNotified,
    required this.onDangerChanged,
    required this.onCurrentChanged,
    required this.onSimulate,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Live Monitor',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ),

          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Monitor human presence around the borewell',
              style: TextStyle(color: Colors.white60),
            ),
          ),

          const SizedBox(height: 20),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              gradient: LinearGradient(
                colors: danger
                    ? [Colors.red.shade900, Colors.red.shade700]
                    : [Colors.blue.shade900, Colors.blue.shade700],
              ),
            ),
            child: Column(
              children: [
                Text(
                  '${currentDistance.toStringAsFixed(1)} m',
                  style: const TextStyle(
                    fontSize: 45,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const Text(
                  'CURRENT DISTANCE',
                  style: TextStyle(letterSpacing: 1.5),
                ),

                const SizedBox(height: 20),

                Icon(
                  personDetected ? Icons.person : Icons.person_off,
                  size: 75,
                  color: personDetected
                      ? Colors.redAccent
                      : Colors.lightGreenAccent,
                ),

                const SizedBox(height: 12),

                Text(
                  personDetected
                      ? (danger
                            ? 'HUMAN DETECTED'
                            : 'HUMAN DETECTED — SAFE DISTANCE')
                      : 'NO PERSON DETECTED',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: personDetected
                        ? (danger ? Colors.redAccent : Colors.orangeAccent)
                        : Colors.lightGreenAccent,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  danger ? '⚠ DANGER ZONE ENTERED' : '✓ System is safe',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          SettingCard(
            title: 'Safety Distance',
            icon: Icons.radar,
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Set Danger Zone',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(
                      '${dangerDistance.toStringAsFixed(1)} m',
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                Slider(
                  value: dangerDistance,
                  min: 1,
                  max: 5,
                  divisions: 8,
                  label: '${dangerDistance.toStringAsFixed(1)} m',
                  onChanged: onDangerChanged,
                ),

                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text('1 m'), Text('3 m'), Text('5 m')],
                ),
              ],
            ),
          ),

          const SizedBox(height: 15),

          SettingCard(
            title: 'Person Distance',
            icon: Icons.social_distance,
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Simulation Distance')),
                    Text(
                      '${currentDistance.toStringAsFixed(1)} m',
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                Slider(
                  value: currentDistance,
                  min: 0.5,
                  max: 5,
                  divisions: 18,
                  label: '${currentDistance.toStringAsFixed(1)} m',
                  onChanged: personDetected ? onCurrentChanged : null,
                ),

                const Text(
                  'First press Simulate Detection, then move this slider.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),

          const SizedBox(height: 15),

          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.06),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                status(
                  'Human Detection',
                  personDetected ? 'DETECTED' : 'NO PERSON',
                  personDetected ? Colors.redAccent : Colors.lightGreenAccent,
                ),
                status(
                  'Danger Zone',
                  danger ? 'ENTERED' : 'CLEAR',
                  danger ? Colors.redAccent : Colors.lightGreenAccent,
                ),
                status(
                  'Warning Alarm',
                  alarmOn ? 'ACTIVE' : 'OFF',
                  alarmOn ? Colors.redAccent : Colors.lightGreenAccent,
                ),
                status(
                  'Owner Notification',
                  ownerNotified ? 'SENT' : 'NOT SENT',
                  ownerNotified ? Colors.orangeAccent : Colors.white54,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton.icon(
              onPressed: personDetected ? null : onSimulate,
              icon: const Icon(Icons.person_search),
              label: const Text(
                'SIMULATE HUMAN DETECTION',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: personDetected ? onClear : null,
              icon: const Icon(Icons.clear),
              label: const Text('CLEAR DETECTION'),
            ),
          ),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget status(String title, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(child: Text(title)),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ALERTS
// ============================================================

class AlertsPage extends StatelessWidget {
  final List<AlertItem> alerts;

  const AlertsPage({super.key, required this.alerts});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Alerts',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),

          const Text(
            'Safety events and notifications',
            style: TextStyle(color: Colors.white60),
          ),

          const SizedBox(height: 20),

          if (alerts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(35),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.06),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 70,
                    color: Colors.lightGreenAccent,
                  ),
                  SizedBox(height: 15),
                  Text(
                    'NO ALERTS',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'No safety events detected.',
                    style: TextStyle(color: Colors.white60),
                  ),
                ],
              ),
            ),

          ...alerts.map((alert) => AlertCard(alert: alert)),

          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

class AlertCard extends StatelessWidget {
  final AlertItem alert;

  const AlertCard({super.key, required this.alert});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.redAccent.withOpacity(.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            backgroundColor: Colors.red,
            child: Icon(Icons.warning),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        alert.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        alert.type,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 7),

                Text(
                  alert.message,
                  style: const TextStyle(color: Colors.white70),
                ),

                const SizedBox(height: 7),

                Text(
                  alert.time,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SAFETY GUIDE
// ============================================================

class SafetyGuidePage extends StatelessWidget {
  const SafetyGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      [
        Icons.lock,
        'Keep the Borewell Covered',
        'Always use a strong and secure cover when the borewell is not in use.',
      ],
      [
        Icons.fence,
        'Create a Safety Boundary',
        'Keep children and unauthorized people away from the borewell area.',
      ],
      [
        Icons.warning,
        'Never Leave It Open',
        'An uncovered borewell can become a serious accident risk.',
      ],
      [
        Icons.radar,
        'Configure Danger Zone',
        'Set a suitable detection distance according to the borewell location.',
      ],
      [
        Icons.notifications_active,
        'Respond to Warnings',
        'When a human enters the danger zone, check the warning immediately.',
      ],
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Safety Guide',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 20),

          ...items.map((item) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.06),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Icon(
                    item[0] as IconData,
                    size: 40,
                    color: Colors.lightGreenAccent,
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item[1] as String,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          item[2] as String,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

// ============================================================
// HOW TO USE
// ============================================================

class HowToUsePage extends StatelessWidget {
  const HowToUsePage({super.key});

  @override
  Widget build(BuildContext context) {
    final steps = [
      [
        '1',
        'Create Account',
        'Create your Borewell Guard owner account.',
        Icons.person_add,
      ],
      [
        '2',
        'Verify Email',
        'Open the Firebase verification email and click the verification link.',
        Icons.mark_email_read,
      ],
      [
        '3',
        'Login',
        'Login using your verified email and password.',
        Icons.login,
      ],
      [
        '4',
        'Open Live Monitor',
        'Open Live Monitor from the bottom navigation.',
        Icons.monitor,
      ],
      [
        '5',
        'Set Danger Zone',
        'Choose a danger zone between 1 and 5 meters.',
        Icons.radar,
      ],
      [
        '6',
        'Simulate Human',
        'Press SIMULATE HUMAN DETECTION.',
        Icons.person_search,
      ],
      [
        '7',
        'Alarm',
        'The warning sound becomes active when the danger zone is entered.',
        Icons.alarm,
      ],
      [
        '8',
        'Check Alert',
        'Open Alerts to see the safety event.',
        Icons.notifications,
      ],
      [
        '9',
        'Clear Detection',
        'Press CLEAR DETECTION after the person leaves.',
        Icons.check_circle,
      ],
    ];

    return DraggableScrollableSheet(
      initialChildSize: .9,
      minChildSize: .5,
      maxChildSize: .95,
      expand: false,
      builder: (_, controller) {
        return ListView(
          controller: controller,
          padding: const EdgeInsets.all(22),
          children: [
            const Center(
              child: Text(
                'How To Use',
                style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
              ),
            ),

            const SizedBox(height: 5),

            const Center(
              child: Text(
                'Borewell Guard User Instructions',
                style: TextStyle(color: Colors.white60),
              ),
            ),

            const SizedBox(height: 22),

            ...steps.map((step) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.06),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.blue,
                      child: Text(
                        step[0] as String,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Icon(
                      step[3] as IconData,
                      color: Colors.lightBlueAccent,
                      size: 28,
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step[1] as String,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            step[2] as String,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(.1),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.orangeAccent.withOpacity(.4)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info, color: Colors.orangeAccent),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Prototype Mode: Human detection can currently be simulated. ESP32 / HC-SR04 / camera data can be connected to Firebase later.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================
// PROFILE
// ============================================================

class ProfilePage extends StatelessWidget {
  final VoidCallback onLogout;

  const ProfilePage({super.key, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          const SizedBox(height: 15),

          const CircleAvatar(
            radius: 52,
            backgroundColor: Colors.blue,
            child: Icon(Icons.person, size: 60),
          ),

          const SizedBox(height: 15),

          Text(
            UserData.fullName,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),

          const Text(
            'Borewell Owner Account',
            style: TextStyle(color: Colors.white60),
          ),

          const SizedBox(height: 28),

          profileItem(Icons.person, 'First Name', UserData.firstName),

          profileItem(
            Icons.person_outline,
            'Last Name',
            UserData.lastName.isEmpty ? 'Not provided' : UserData.lastName,
          ),

          profileItem(Icons.email, 'Registered Email', UserData.email),

          profileItem(Icons.phone, 'Mobile Number', UserData.mobile),

          profileItem(Icons.security, 'System', 'Borewell Guard'),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout),
              label: const Text('LOGOUT'),
            ),
          ),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget profileItem(IconData icon, String title, String value) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.lightBlueAccent),

          const SizedBox(width: 15),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// STATUS CARD
// ============================================================

class StatusCard extends StatelessWidget {
  final bool safe;
  final bool personDetected;

  const StatusCard({
    super.key,
    required this.safe,
    required this.personDetected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: safe
              ? [Colors.green.shade800, Colors.green.shade600]
              : [Colors.red.shade900, Colors.red.shade700],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Icon(safe ? Icons.verified_user : Icons.warning, size: 55),

          const SizedBox(width: 15),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  safe ? 'SYSTEM SAFE' : 'DANGER DETECTED',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  safe
                      ? (personDetected
                            ? 'Person detected but outside danger zone'
                            : 'No person detected')
                      : 'Person detected inside danger zone',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// INFO CARD
// ============================================================

class InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const InfoCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.cyanAccent, size: 28),

          const SizedBox(height: 10),

          Text(
            title,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),

          const SizedBox(height: 4),

          Text(
            value,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SETTING CARD
// ============================================================

class SettingCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const SettingCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.lightBlueAccent),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          child,
        ],
      ),
    );
  }
}

// ============================================================
// ALERT MODEL
// ============================================================

class AlertItem {
  final String title;
  final String message;
  final String time;
  final String type;

  AlertItem({
    required this.title,
    required this.message,
    required this.time,
    required this.type,
  });
}
