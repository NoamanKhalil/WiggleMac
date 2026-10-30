.PHONY: app run dmg release clean

app:
	scripts/build-app.sh release

run: app
	open build/Wiggle.app

# A DMG to try on this Mac. Other Macs will refuse it until it's built with `make release`.
dmg:
	scripts/release.sh --local

# Developer ID signed and notarized DMG, plus the update feed. See Releasing in README.md.
release:
	scripts/release.sh

clean:
	rm -rf .build build
