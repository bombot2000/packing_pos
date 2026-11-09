from pathlib import Path
import re
import sys

candidates = [
    Path("android/app/build.gradle.kts"),
    Path("android/app/build.gradle"),
]
gradle = next((path for path in candidates if path.exists()), None)
if gradle is None:
    raise SystemExit("Android app Gradle file was not generated.")

text = gradle.read_text()
is_kotlin = gradle.suffix == ".kts"

if is_kotlin:
    imports = (
        "import java.io.FileInputStream\n"
        "import java.util.Properties\n\n"
        "val keystoreProperties = Properties()\n"
        "val keystorePropertiesFile = rootProject.file(\"key.properties\")\n"
        "if (keystorePropertiesFile.exists()) {\n"
        "    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n"
        "}\n\n"
    )
    if "val keystoreProperties = Properties()" not in text:
        text = imports + text
    signing = (
        "    signingConfigs {\n"
        "        create(\"release\") {\n"
        "            keyAlias = keystoreProperties[\"keyAlias\"] as String\n"
        "            keyPassword = keystoreProperties[\"keyPassword\"] as String\n"
        "            storeFile = file(keystoreProperties[\"storeFile\"] as String)\n"
        "            storePassword = keystoreProperties[\"storePassword\"] as String\n"
        "        }\n"
        "    }\n\n"
    )
    if 'create("release")' not in text:
        marker = "    buildTypes {"
        if marker not in text:
            raise SystemExit("Could not locate buildTypes block in Gradle Kotlin file.")
        text = text.replace(marker, signing + marker, 1)
    if 'signingConfig = signingConfigs.getByName("release")' not in text:
        text = re.sub(
            r'(release\\s*\\{[\\s\\S]*?)(signingConfig\\s*=\\s*signingConfigs\\.getByName\\(\"debug\"\\))',
            r'\\1signingConfig = signingConfigs.getByName("release")',
            text,
            count=1,
        )
        if 'signingConfig = signingConfigs.getByName("release")' not in text:
            text = re.sub(
                r'(release\\s*\\{)',
                r'\\1\\n            signingConfig = signingConfigs.getByName("release")',
                text,
                count=1,
            )
else:
    imports = (
        "def keystoreProperties = new Properties()\n"
        "def keystorePropertiesFile = rootProject.file('key.properties')\n"
        "if (keystorePropertiesFile.exists()) {\n"
        "    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))\n"
        "}\n\n"
    )
    if "def keystoreProperties = new Properties()" not in text:
        text = imports + text
    signing = (
        "    signingConfigs {\n"
        "        release {\n"
        "            keyAlias keystoreProperties['keyAlias']\n"
        "            keyPassword keystoreProperties['keyPassword']\n"
        "            storeFile file(keystoreProperties['storeFile'])\n"
        "            storePassword keystoreProperties['storePassword']\n"
        "        }\n"
        "    }\n\n"
    )
    if "signingConfigs {" not in text:
        marker = "    buildTypes {"
        if marker not in text:
            raise SystemExit("Could not locate buildTypes block in Gradle file.")
        text = text.replace(marker, signing + marker, 1)
    if "signingConfig signingConfigs.release" not in text:
        text = re.sub(
            r"(release\\s*\\{)(?![\\s\\S]*?signingConfig)",
            r"\\1\\n            signingConfig signingConfigs.release",
            text,
            count=1,
        )
        text = text.replace("signingConfig signingConfigs.debug", "signingConfig signingConfigs.release", 1)

gradle.write_text(text)
print(f"Configured persistent release signing in {gradle}.")
