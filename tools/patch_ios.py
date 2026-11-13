"""Patch the generated iOS project: iOS 16 minimum, Chinese name, doc types."""

import os
import re
import sys

PBX = os.path.join("ios", "Runner.xcodeproj", "project.pbxproj")
PLIST = os.path.join("ios", "Runner", "Info.plist")

APP_NAME = "书卷"
BUNDLE_NAME = "书卷"


def patch_pbx():
    with open(PBX, "r", encoding="utf-8", newline="") as f:
        src = f.read()
    n = len(re.findall(r"IPHONEOS_DEPLOYMENT_TARGET = 15\.0;", src))
    src = src.replace("IPHONEOS_DEPLOYMENT_TARGET = 15.0;", "IPHONEOS_DEPLOYMENT_TARGET = 16.0;")
    m = len(re.findall(r"IPHONEOS_DEPLOYMENT_TARGET = 13\.0;", src))
    src = src.replace("IPHONEOS_DEPLOYMENT_TARGET = 13.0;", "IPHONEOS_DEPLOYMENT_TARGET = 16.0;")
    with open(PBX, "w", encoding="utf-8", newline="") as f:
        f.write(src)
    print("deployment target patched:", n + m)


DOC_TYPES = """\t<key>CFBundleDocumentTypes</key>
\t<array>
\t\t<dict>
\t\t\t<key>CFBundleTypeName</key>
\t\t\t<string>EPUB 电子书</string>
\t\t\t<key>LSHandlerRank</key>
\t\t\t<string>Owner</string>
\t\t\t<key>LSItemContentTypes</key>
\t\t\t<array>
\t\t\t\t<string>org.idpf.epub-container</string>
\t\t\t</array>
\t\t</dict>
\t\t<dict>
\t\t\t<key>CFBundleTypeName</key>
\t\t\t<string>纯文本</string>
\t\t\t<key>LSHandlerRank</key>
\t\t\t<string>Alternate</string>
\t\t\t<key>LSItemContentTypes</key>
\t\t\t<array>
\t\t\t\t<string>public.plain-text</string>
\t\t\t</array>
\t\t</dict>
\t</array>
\t<key>LSSupportsOpeningDocumentsInPlace</key>
\t<true/>
\t<key>UIFileSharingEnabled</key>
\t<true/>
"""


def patch_plist():
    with open(PLIST, "r", encoding="utf-8", newline="") as f:
        src = f.read()
    src = src.replace(
        "<key>CFBundleDisplayName</key>\r\n\t<string>Bookleaf</string>",
        f"<key>CFBundleDisplayName</key>\r\n\t<string>{APP_NAME}</string>",
    )
    src = src.replace(
        "<key>CFBundleDisplayName</key>\n\t<string>Bookleaf</string>",
        f"<key>CFBundleDisplayName</key>\n\t<string>{APP_NAME}</string>",
    )
    src = re.sub(
        r"<key>CFBundleName</key>\s*<string>[^<]*</string>",
        f"<key>CFBundleName</key>\n\t<string>{BUNDLE_NAME}</string>",
        src,
    )
    if "CFBundleDocumentTypes" not in src:
        idx = src.find("<key>LSRequiresIPhoneOS</key>")
        if idx < 0:
            raise SystemExit("cannot find LSRequiresIPhoneOS in Info.plist")
        src = src[:idx] + DOC_TYPES.replace("\n", "\r\n") + src[idx:]
    with open(PLIST, "w", encoding="utf-8", newline="") as f:
        f.write(src)
    print("Info.plist patched")


if __name__ == "__main__":
    patch_pbx()
    patch_plist()
