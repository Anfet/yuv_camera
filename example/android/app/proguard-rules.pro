# ML Kit creates its component registrars by reflection through the no-argument constructor;
# R8 full mode removes it unless it is kept explicitly.
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
