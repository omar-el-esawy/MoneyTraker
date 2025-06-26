import 'package:flutter/material.dart';
import 'package:money_traker/pages/splash_screen.dart';
import 'package:money_traker/pages/home_page.dart';
import 'package:money_traker/constants/app_constants.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppConstants.primaryColor,
          primary: AppConstants.primaryColor,
          secondary: AppConstants.secondaryColor,
          background: AppConstants.backgroundColor,
          error: AppConstants.errorColor,
        ),
        scaffoldBackgroundColor: AppConstants.backgroundColor,
        textTheme: GoogleFonts.latoTextTheme(
          Theme.of(context).textTheme.copyWith(
            displayLarge: GoogleFonts.lato(fontSize: 48, fontWeight: FontWeight.bold),
            displayMedium: GoogleFonts.lato(fontSize: 36, fontWeight: FontWeight.bold),
            displaySmall: GoogleFonts.lato(fontSize: 28, fontWeight: FontWeight.w600),
            headlineLarge: GoogleFonts.lato(fontSize: 24, fontWeight: FontWeight.bold),
            headlineMedium: GoogleFonts.lato(fontSize: 20, fontWeight: FontWeight.w600),
            headlineSmall: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.w600),
            titleLarge: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.w500),
            titleMedium: GoogleFonts.lato(fontSize: 16, fontWeight: FontWeight.w500),
            titleSmall: GoogleFonts.lato(fontSize: 14, fontWeight: FontWeight.w500),
            bodyLarge: GoogleFonts.lato(fontSize: 16),
            bodyMedium: GoogleFonts.lato(fontSize: 14),
            bodySmall: GoogleFonts.lato(fontSize: 12),
            labelLarge: GoogleFonts.lato(fontSize: 14, fontWeight: FontWeight.w600),
            labelMedium: GoogleFonts.lato(fontSize: 12, fontWeight: FontWeight.w600),
            labelSmall: GoogleFonts.lato(fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ),
        useMaterial3: true,
      ),
      home: const SplashToHome(),
    );
  }
}

class SplashToHome extends StatefulWidget {
  const SplashToHome({super.key});

  @override
  State<SplashToHome> createState() => _SplashToHomeState();
}

class _SplashToHomeState extends State<SplashToHome> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    // Simulate loading or wait for any async initialization if needed
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) {
      setState(() {
        _ready = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const SplashScreen();
    }
    return const HomePage();
  }
}
