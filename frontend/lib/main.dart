import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:device_preview/device_preview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'dart:async';

import 'core/theme/app_theme.dart';
import 'features/chat/presentation/chat_page.dart';
import 'features/chat/bloc/chat_bloc.dart';
import 'services/ai_service.dart';
import 'features/profile/data/profile_service.dart';
import 'screens/pc_connection_screen.dart';

// Main configuration - update IP based on your PC's IP or connect dynamically
const String defaultBackendUrl = 'http://10.0.2.2:8000'; // Default Android emulator localhost

void main() {
  // Global error handling to prevent crashes
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    print('❌ Flutter Error: ${details.exception}');
  };
  
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    
    runApp(
      DevicePreview(
        // Disable device preview for production
        enabled: false,
        builder: (context) => const MedAssistAppApp(),
      ),
    );
  }, (error, stackTrace) {
    print('❌ Uncaught Error: $error');
    print('Stack trace: $stackTrace');
  });
}

class MedAssistAppApp extends StatelessWidget {
  const MedAssistAppApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AIService>(
          create: (_) {
            String baseUrl = defaultBackendUrl;
            try {
              if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
                baseUrl = 'http://127.0.0.1:8000'; 
              }
            } catch (_) {}
            return AIService(baseUrl: baseUrl);
          },
        ),
        RepositoryProvider<ProfileService>(
          create: (_) {
            String baseUrl = defaultBackendUrl;
            try {
              if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
                baseUrl = 'http://127.0.0.1:8000';
              }
            } catch (_) {}
            return ProfileService(baseUrl: baseUrl);
          },
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ChatBloc>(
            create: (context) => ChatBloc(),  // On-device Med Assist App
          ),
        ],
        child: MaterialApp(
          title: 'Med Assist App',
          debugShowCheckedModeBanner: false,
          
          // Device Preview integration
          useInheritedMediaQuery: true,
          locale: DevicePreview.locale(context),
          builder: DevicePreview.appBuilder,
          
          // Theme
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark, // Dark theme
          
          // Start with model init screen
          home: const AppStartupScreen(),
        ),
      ),
    );
  }
}

/// Startup screen that handles PC connection
class AppStartupScreen extends StatefulWidget {
  const AppStartupScreen({super.key});

  @override
  State<AppStartupScreen> createState() => _AppStartupScreenState();
}

class _AppStartupScreenState extends State<AppStartupScreen> {
  bool _isConnected = false;

  @override
  Widget build(BuildContext context) {
    if (_isConnected) {
      return const ChatPage();
    }
    
    return PCConnectionScreen(
      onConnected: () {
        setState(() {
          _isConnected = true;
        });
        // Initialize chat with PC backend
        context.read<ChatBloc>().add(ChatInitialized());
      },
      onSkip: () {
        setState(() {
          _isConnected = true;
        });
        // Initialize anyway (will prompt to connect in chat)
        context.read<ChatBloc>().add(ChatInitialized());
      },
    );
  }
}
