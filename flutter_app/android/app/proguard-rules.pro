# Extra R8 rules for release builds (see app/build.gradle.kts). Flutter, Firebase and AndroidX
# bring their own keep rules; only add what a release build on a real phone shows is missing.

# Flutter's engine refers to Play Core (deferred components), which this app doesn't include.
-dontwarn com.google.android.play.core.**
