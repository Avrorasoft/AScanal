import org.jetbrains.kotlin.gradle.tasks.KotlinCompile
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// INYECCIÓN DE AVRORA SOFT: Le dice a Android de dónde descargar Firebase
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.gms:google-services:4.4.1")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// CLASE SIMULADORA DE FLUTTER PARA COMPATIBILIDAD
// Provee las propiedades exactas que buscan los plugins antiguos como geolocator
open class FlutterMock {
    val source = ""
    val compileSdkVersion = 34
    val minSdkVersion = 21
    val targetSdkVersion = 34
}

// Interceptor preventivo con plugins.withId para inyectar 'flutter' y 'compileSdk' antes de la evaluación
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            if (compileSdk == null) {
                compileSdk = 34
            }
            try {
                val extAware = this as org.gradle.api.plugins.ExtensionAware
                if (extAware.extensions.findByName("flutter") == null) {
                    extAware.extensions.add("flutter", FlutterMock())
                }
            } catch (e: Exception) {}
        }
    }
    plugins.withId("com.android.application") {
        extensions.configure<com.android.build.gradle.AppExtension>("android") {
            try {
                val extAware = this as org.gradle.api.plugins.ExtensionAware
                if (extAware.extensions.findByName("flutter") == null) {
                    extAware.extensions.add("flutter", FlutterMock())
                }
            } catch (e: Exception) {}
        }
    }
}

// Directiva Maestra de Avrora Soft - Vibola LLC: 
// Fuerza la compatibilidad JVM 17 en todos los módulos de terceros usando el DSL moderno
// y configuración perezosa (lazy) sin interferir en la evaluación del proyecto.
subprojects {
    tasks.withType(KotlinCompile::class.java).configureEach {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }
}

// =============================================================================
// PARCHE MAESTRO DE AVRORA SOFT PARA COMPATIBILIDAD DE LIBRERÍAS ANTIGUAS
// Inyecta dinámicamente el 'namespace' faltante usando Kotlin Reflection
// =============================================================================
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            try {
                val getNamespace = androidExt.javaClass.getMethod("getNamespace")
                val currentNamespace = getNamespace.invoke(androidExt)
                
                if (currentNamespace == null) {
                    val setNamespace = androidExt.javaClass.getMethod("setNamespace", String::class.java)
                    var fallbackNamespace = project.group.toString()
                    
                    if (fallbackNamespace.isEmpty()) {
                        fallbackNamespace = "com.avrorasoft." + project.name.replace("-", "_")
                    }
                    
                    setNamespace.invoke(androidExt, fallbackNamespace)
                }
            } catch (e: Exception) {
                // Ignoramos silenciosamente si la extensión de Android es distinta a la esperada
            }
        }
    }
}

subprojects {
    afterEvaluate {
        if (hasProperty("android")) {
            extensions.configure<com.android.build.gradle.BaseExtension>("android") {
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
        }
    }
    
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}