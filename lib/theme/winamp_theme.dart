import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class WinampTheme {
  static const Color winampBg = Color(0xFF1E1E24);
  static const Color winampPanelBg = Color(0xFF0F0F12);
  static const Color winampDisplayBg = Color(0xFF000000);
  static const Color winampTextGreen = Color(0xFF00FF00);
  static const Color winampTextBlue = Color(0xFF00E5FF);
  static const Color winampBorder = Color(0xFF3A3A42);

  static ThemeData get darkTheme {
    final textTheme = GoogleFonts.ibmPlexMonoTextTheme(ThemeData.dark().textTheme);
    
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: winampBg,
      appBarTheme: AppBarTheme(
        backgroundColor: winampPanelBg,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white70),
        titleTextStyle: GoogleFonts.silkscreen(
          color: Colors.white70,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
        ),
      ),
      textTheme: textTheme,
      colorScheme: ColorScheme.fromSeed(
        seedColor: winampBg,
        brightness: Brightness.dark,
        surface: winampPanelBg,
      ),
      extensions: <ThemeExtension<dynamic>>[
        WinampColors(
          bg: winampBg,
          panelBg: winampPanelBg,
          displayBg: winampDisplayBg,
          textGreen: winampTextGreen,
          textBlue: winampTextBlue,
          border: winampBorder,
          // Custom font styles for Winamp elements
          displayStyle: GoogleFonts.vt323(
            color: winampTextGreen,
            fontSize: 32,
          ),
          statusStyle: GoogleFonts.ibmPlexMono(
            color: winampTextBlue,
            fontSize: 10,
          ),
          tickerStyle: GoogleFonts.vt323(
            color: winampTextGreen,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
          playlistStyle: GoogleFonts.ibmPlexMono(
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class WinampColors extends ThemeExtension<WinampColors> {
  final Color? bg;
  final Color? panelBg;
  final Color? displayBg;
  final Color? textGreen;
  final Color? textBlue;
  final Color? border;
  
  // Typography Extensions
  final TextStyle? displayStyle;
  final TextStyle? statusStyle;
  final TextStyle? tickerStyle;
  final TextStyle? playlistStyle;

  WinampColors({
    this.bg,
    this.panelBg,
    this.displayBg,
    this.textGreen,
    this.textBlue,
    this.border,
    this.displayStyle,
    this.statusStyle,
    this.tickerStyle,
    this.playlistStyle,
  });

  @override
  WinampColors copyWith({
    Color? bg,
    Color? panelBg,
    Color? displayBg,
    Color? textGreen,
    Color? textBlue,
    Color? border,
    TextStyle? displayStyle,
    TextStyle? statusStyle,
    TextStyle? tickerStyle,
    TextStyle? playlistStyle,
  }) {
    return WinampColors(
      bg: bg ?? this.bg,
      panelBg: panelBg ?? this.panelBg,
      displayBg: displayBg ?? this.displayBg,
      textGreen: textGreen ?? this.textGreen,
      textBlue: textBlue ?? this.textBlue,
      border: border ?? this.border,
      displayStyle: displayStyle ?? this.displayStyle,
      statusStyle: statusStyle ?? this.statusStyle,
      tickerStyle: tickerStyle ?? this.tickerStyle,
      playlistStyle: playlistStyle ?? this.playlistStyle,
    );
  }

  @override
  WinampColors lerp(ThemeExtension<WinampColors>? other, double t) {
    if (other is! WinampColors) {
      return this;
    }
    return WinampColors(
      bg: Color.lerp(bg, other.bg, t),
      panelBg: Color.lerp(panelBg, other.panelBg, t),
      displayBg: Color.lerp(displayBg, other.displayBg, t),
      textGreen: Color.lerp(textGreen, other.textGreen, t),
      textBlue: Color.lerp(textBlue, other.textBlue, t),
      border: Color.lerp(border, other.border, t),
      displayStyle: TextStyle.lerp(displayStyle, other.displayStyle, t),
      statusStyle: TextStyle.lerp(statusStyle, other.statusStyle, t),
      tickerStyle: TextStyle.lerp(tickerStyle, other.tickerStyle, t),
      playlistStyle: TextStyle.lerp(playlistStyle, other.playlistStyle, t),
    );
  }
}

