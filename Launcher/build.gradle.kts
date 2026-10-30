plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
    namespace = "id.npc.aoe2launcher"
    compileSdk = 36
    defaultConfig {
        applicationId = "id.npc.aoe2launcher"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
        ndk { abiFilters += (project.findProperty("testAbi")?.toString() ?: "arm64-v8a") }
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    packaging { jniLibs { useLegacyPackaging = true } }
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("generated/gameAssets"))
    androidResources { noCompress += "pck" }
}
val engine = providers.environmentVariable("GODOT_BIN").orElse("godot")
val importGame by tasks.registering(Exec::class) {
    workingDir(rootDir)
    commandLine(engine.get(), "--headless", "--path", "godot_game", "--editor", "--import")
}
val packGame by tasks.registering(Exec::class) {
    dependsOn(importGame)
    val out = layout.buildDirectory.file("generated/gameAssets/game.pck")
    doFirst { out.get().asFile.parentFile.mkdirs() }
    workingDir(rootDir)
    commandLine(engine.get(), "--headless", "--path", "godot_game", "--export-pack", "Launcher PCK", out.get().asFile.absolutePath)
}
tasks.named("preBuild") { dependsOn(packGame) }
dependencies {
    implementation("org.godotengine:godot:4.7.2.stable")
    implementation("androidx.fragment:fragment:1.8.6")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250107")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}
