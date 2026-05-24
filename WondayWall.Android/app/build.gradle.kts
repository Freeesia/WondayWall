import com.android.build.api.dsl.ApplicationExtension

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

val releaseKeystoreFile = providers.environmentVariable("ANDROID_KEYSTORE_FILE").orNull
val releaseKeystorePassword = providers.environmentVariable("ANDROID_KEYSTORE_PASSWORD").orNull
val releaseKeyAlias = providers.environmentVariable("ANDROID_KEY_ALIAS").orNull
val releaseKeyPassword = providers.environmentVariable("ANDROID_KEY_PASSWORD").orNull
// Preview APK は更新互換性のため、リポジトリ内の固定デバッグ用キーで署名する。
val previewKeystoreFile = file("preview-debug.keystore")
val hasReleaseSigningConfig = listOf(
    releaseKeystoreFile,
    releaseKeystorePassword,
    releaseKeyAlias,
    releaseKeyPassword
).all { !it.isNullOrBlank() }

configure<ApplicationExtension> {
    namespace = "com.studiofreesia.wondaywall"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.studiofreesia.wondaywall"
        minSdk = 26
        targetSdk = 37
        versionCode = providers.gradleProperty("wondaywallVersionCode")
            .orElse("1")
            .get()
            .toInt()
        versionName = providers.gradleProperty("wondaywallVersionName")
            .orElse("0.0")
            .get()

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        create("preview") {
            storeFile = previewKeystoreFile
            storePassword = "android"
            keyAlias = "wondaywall-preview"
            keyPassword = "android"
        }

        if (hasReleaseSigningConfig) {
            create("release") {
                storeFile = file(releaseKeystoreFile!!)
                storePassword = releaseKeystorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".local"
            versionNameSuffix = "-local"
            buildConfigField("boolean", "DEBUG_FEATURES_ENABLED", "true")
        }

        release {
            buildConfigField("boolean", "DEBUG_FEATURES_ENABLED", "false")
            if (hasReleaseSigningConfig) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }

        create("preview") {
            initWith(getByName("release"))
            applicationIdSuffix = ".preview"
            versionNameSuffix = "-preview"
            signingConfig = signingConfigs.getByName("preview")
            buildConfigField("boolean", "DEBUG_FEATURES_ENABLED", "true")
            matchingFallbacks += listOf("release")
        }
    }

    sourceSets {
        getByName("preview") {
            kotlin.srcDir("src/debug/kotlin")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }


    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
            excludes += "/META-INF/INDEX.LIST"
            excludes += "/META-INF/DEPENDENCIES"
            // Google GenAI の shaded KotlinModule 参照が未変換の service entry を除外する。
            excludes += "/META-INF/services/com.fasterxml.jackson.databind.Module"
        }
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)

    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.work.runtime.ktx)
    implementation(libs.androidx.datastore.preferences)

    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.datetime)

    // API キー暗号化（Tink）
    implementation(libs.tink.android)

    // Google AI（Gemini API）
    implementation(libs.google.genai)

    // HTTP / RSS / OGP
    implementation(libs.okhttp)
    implementation(libs.rssparser)
    implementation(libs.jsoup)

    // 画像表示
    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)

    debugImplementation(libs.androidx.compose.ui.tooling)
    add("previewImplementation", libs.androidx.compose.ui.tooling)

    androidTestImplementation(libs.androidx.work.testing)
}
