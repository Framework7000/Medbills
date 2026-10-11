# ML Kit text recognition: only the Latin model is bundled. The plugin also
# references the Chinese/Devanagari/Japanese/Korean models, which are
# intentionally not included.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
