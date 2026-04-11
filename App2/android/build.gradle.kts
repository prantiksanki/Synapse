import java.io.File

fun Project.applyNamespaceFromManifest() {
    val androidExtension = extensions.findByName("android") ?: return
    val getNamespace = androidExtension.javaClass.methods.firstOrNull {
        it.name == "getNamespace" && it.parameterCount == 0
    } ?: return
    val currentNamespace = getNamespace.invoke(androidExtension) as? String
    if (!currentNamespace.isNullOrBlank()) return

    val manifestFile = File(projectDir, "src/main/AndroidManifest.xml")
    if (!manifestFile.exists()) return

    val manifestText = manifestFile.readText()
    val packageName = Regex("package\\s*=\\s*\"([^\"]+)\"")
        .find(manifestText)
        ?.groupValues
        ?.getOrNull(1)
        ?.trim()
    if (packageName.isNullOrBlank()) return

    val setNamespace = androidExtension.javaClass.methods.firstOrNull {
        it.name == "setNamespace" && it.parameterCount == 1
    } ?: return
    setNamespace.invoke(androidExtension, packageName)
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
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    pluginManager.withPlugin("com.android.library") {
        applyNamespaceFromManifest()
    }
    pluginManager.withPlugin("com.android.application") {
        applyNamespaceFromManifest()
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
