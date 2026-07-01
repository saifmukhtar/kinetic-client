# Keep androidx.work classes that R8 is aggressively stripping
-keep class androidx.work.** { *; }
-keep class androidx.work.impl.** { *; }
-keepclassmembers class androidx.work.impl.WorkDatabase_Impl {
    <init>();
}

# Keep androidx.startup classes
-keep class androidx.startup.** { *; }
