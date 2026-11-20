# Flutter wrapper & app classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class app.lightnovel.shelf.plus.** { *; }

# Keep WebView JS bridge methods (used by cloudflare_turnstile / flutter_inappwebview)
-keepattributes *Annotation*
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keep class com.pichillilorenzo.flutter_inappwebview_android.** { *; }

# Keep Tink / EncryptedSharedPreferences / Gson models used by flutter_secure_storage
-keep class com.google.crypto.tink.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.google.crypto.tink.**
-dontwarn com.google.android.play.core.**
-dontwarn javax.annotation.**
-dontwarn org.codehaus.mojo.animal_sniffer.IgnoreJRERequirement
