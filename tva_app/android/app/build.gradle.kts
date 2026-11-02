// Archivo completo: android/app/build.gradle.kts
// Configuración específica del módulo app para com.avrorasoft.tva

import java.util.Properties
import java.io.FileInputStream

// Carga las propiedades locales para obtener las variables de versión de Flutter
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.apply {
        load(FileInputStream(localPropertiesFile))
    }
}

val flutterVersionCode = localProperties.getProperty("flutter.versionCode")?.toInt() ?: 1
val flutterVersionName = localProperties.getProperty("flutter.versionName") ?: "1.0.0"

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    // ¡LÍNEA CRÍTICA AÑADIDA PARA QUE LEA EL JSON DE FIREBASE!
    id("com.google.gms.google-services")
}

android {
    // Definición de identidad única para la aplicación
    namespace = "com.avrorasoft.tva"
    compileSdk = 36

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }

    defaultConfig {
        // El applicationId debe coincidir con el namespace para evitar errores de manifiesto
        applicationId = "com.avrorasoft.tva"
        
        // Valores extraídos correctamente a la manera de KTS
        minSdk = 21 // La API mínima recomendada para Firebase y Flutter moderno
        targetSdk = 34 // Alineado con el SDK de compilación del proyecto
        versionCode = flutterVersionCode
        versionName = flutterVersionName
    }

     buildTypes {
        release {
            // Configuración de firma para producción
            signingConfig = signingConfigs.getByName("debug") 
            // Variables booleanas con la sintaxis correcta de Kotlin DSL
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // Actualización crítica de Avrora Soft: Elevamos a Java 17 para eliminar
    // las advertencias de obsolescencia y sincronizar con Kotlin
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

// Sincronización del compilador de Kotlin para que trabaje exactamente
// en la misma versión 17 que el motor de Java
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Implementación de dependencias estándar de Android
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk7")
}