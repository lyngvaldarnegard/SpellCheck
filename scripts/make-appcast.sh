#!/bin/sh
# Generates appcast.xml (the Sparkle update feed) for a release.
#
# Usage:
#   scripts/make-appcast.sh v0.1.0 build/SpellCheck-macOS.zip [edSignature]
set -euo pipefail

VERSION="$1"
ZIP="$2"
SIGNATURE="${3:-}"
REPO="lyngvaldarnegard/SpellCheck"

if [ ! -f "$ZIP" ]; then
    echo "zip not found: $ZIP" >&2
    exit 1
fi

if stat -f %z "$ZIP" >/dev/null 2>&1; then
    SIZE=$(stat -f %z "$ZIP")
else
    SIZE=$(stat -c %s "$ZIP")
fi

URL="https://github.com/$REPO/releases/download/$VERSION/$(basename "$ZIP")"
DATE=$(date -u '+%a, %d %b %Y %H:%M:%S +0000')
SHORT="${VERSION#v}"

{
    echo '<?xml version="1.0" encoding="utf-8"?>'
    echo '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
    echo '  <channel>'
    echo '    <title>SpellCheck Releases</title>'
    echo "    <link>https://github.com/$REPO/releases</link>"
    echo '    <description>SpellCheck updates</description>'
    echo '    <language>en</language>'
    echo '    <item>'
    echo "      <title>Version $SHORT</title>"
    echo "      <pubDate>$DATE</pubDate>"
    echo "      <sparkle:shortVersionString>$SHORT</sparkle:shortVersionString>"
    echo "      <sparkle:version>$SHORT</sparkle:version>"
    if [ -n "$SIGNATURE" ]; then
        echo "      <enclosure url=\"$URL\" sparkle:edSignature=\"$SIGNATURE\" length=\"$SIZE\" type=\"application/octet-stream\"/>"
    else
        echo "      <enclosure url=\"$URL\" length=\"$SIZE\" type=\"application/octet-stream\"/>"
    fi
    echo '    </item>'
    echo '  </channel>'
    echo '</rss>'
} > appcast.xml

echo "Wrote appcast.xml for $VERSION"
