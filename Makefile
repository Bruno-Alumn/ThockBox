APP := Thockbox
NAME := ThockBox
BUILD := .build/release
BUNDLE := dist/$(NAME).app
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
ZIP := dist/$(NAME)-$(VERSION).zip
DMG := dist/$(NAME)-$(VERSION).dmg
# How builds are signed (see docs/RELEASING.md):
#   SIGNING=developer-id  the maintainer's Developer ID (the default, and what
#                         releases use); `make dmg` and `make release` also
#                         notarize and staple
#   SIGNING=thockbox      the self-signed "ThockBox Signing" certificate
#                         (`make signing-cert`), ad-hoc ("-") if this Mac
#                         doesn't have it, where every rebuild needs a new grant
# Both carry packaging/designated_requirement.txt, so permissions and updates
# carry over from one to the other.
SIGNING ?= developer-id
DEVELOPER_ID := Developer ID Application: Bruno Cassina (22R95V8NA5)
ifeq ($(SIGNING),developer-id)
# Ad-hoc where the identity isn't installed (CI, contributors' Macs).
CODESIGN_ID ?= $(if $(shell security find-identity -v -p codesigning 2>/dev/null | grep -F '"$(DEVELOPER_ID)"'),$(DEVELOPER_ID),-)
else
CODESIGN_ID ?= $(or $(shell security find-identity -p codesigning 2>/dev/null | awk -F'"' '/"ThockBox Signing"/ {split($$1, a, " "); print a[2]; exit}'),-)
endif

.PHONY: all build bundle zip dmg release cask signing-cert test bench sounds icon clean run

all: bundle

build:
	swift build -c release

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(BUILD)/$(APP) $(BUNDLE)/Contents/MacOS/
	# Local symbols are only for debugging; dropping them halves the binary.
	strip -x $(BUNDLE)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(BUNDLE)/Contents/
	cp Resources/Thockbox.sdef $(BUNDLE)/Contents/Resources/
	cp -R Resources/Sounds $(BUNDLE)/Contents/Resources/Sounds
	cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/
	scripts/build_icon_assets.sh $(BUNDLE)
	cp CHANGELOG.md $(BUNDLE)/Contents/Resources/
	scripts/build_intents_metadata.sh $(BUNDLE)
	scripts/sign_app.sh $(BUNDLE) "$(CODESIGN_ID)"
	@du -sh $(BUNDLE)
	@if [ "$(CODESIGN_ID)" = "-" ]; then \
		echo "note: ad-hoc signed. Run 'make signing-cert' so the Accessibility grant survives rebuilds."; \
	fi

# One-time setup: a self-signed identity that every build is signed with.
signing-cert:
	scripts/make_signing_cert.sh

# Rebuild the sound catalog from upstream sources (requires uv + network).
sounds:
	uv run --with soundfile,numpy scripts/build_sounds.py

# Rebuild Resources/AppIcon.icns (and docs/logo.png) from the logo artwork.
# That's the icon for macOS 13 to 15; macOS 26 shows the Liquid Glass
# Resources/AppIcon.icon (edit it in Icon Composer).
icon:
	swift scripts/make_icon.swift art/logo-source.png Resources/AppIcon.icns docs/logo.png

# Unit tests, a headless audio smoke test that decodes and plays every pack,
# then a check that the launched app settles down (scripts/launch_check.sh).
test: bundle
	swift test
	$(BUNDLE)/Contents/MacOS/$(APP) --test-audio
	scripts/launch_check.sh $(BUNDLE)

# Performance checks: CPU per key press and idle CPU (see scripts/bench).
bench:
	mkdir -p .build/bench
	swiftc -O -suppress-warnings -o .build/bench/thockbox-bench scripts/bench/main.swift \
		$(filter-out Sources/$(APP)/$(APP)App.swift,$(wildcard Sources/$(APP)/*.swift Sources/$(APP)/UI/*.swift))
	.build/bench/thockbox-bench Resources/Sounds

run: bundle
	open $(BUNDLE)

# A zip of the app that's ready to send or attach (keeps the signature).
zip: bundle
	rm -f $(ZIP)
	ditto -c -k --keepParent --sequesterRsrc $(BUNDLE) $(ZIP)
	@echo "$(ZIP)"

# The disk image people download: the app next to an Applications link.
dmg: bundle
	@if [ "$(CODESIGN_ID)" = "$(DEVELOPER_ID)" ]; then scripts/notarize.sh $(BUNDLE); fi
	scripts/make_dmg.sh $(BUNDLE) $(DMG) "$(CODESIGN_ID)"
	@if [ "$(CODESIGN_ID)" = "$(DEVELOPER_ID)" ]; then scripts/notarize.sh $(DMG); fi

# Publish the disk image as GitHub release v<version>. GitHub adds the
# source archives itself. The app's updater installs from the newest
# release's ThockBox-<version>.dmg.
release: dmg cask
	@if [ "$(CODESIGN_ID)" = "-" ]; then echo "refusing to release an ad-hoc build; the Developer ID isn't in this Mac's keychain (docs/RELEASING.md)"; exit 1; fi
	scripts/release_notes.sh $(VERSION) > dist/notes.md
	gh release create v$(VERSION) $(DMG) --title "ThockBox $(VERSION)" --notes-file dist/notes.md
	@echo "Now copy packaging/thockbox.rb to Casks/thockbox.rb in Bruno-Alumn/homebrew-thockbox."

# Point the Homebrew cask (packaging/thockbox.rb) at this version's disk image.
cask: dmg
	scripts/update_cask.sh $(VERSION) $(DMG)

clean:
	rm -rf .build dist/$(NAME).app dist/$(NAME)-*.zip dist/$(NAME)-*.dmg
