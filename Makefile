APP := Thockbox
NAME := ThockBox
BUILD := .build/release
BUNDLE := dist/$(NAME).app
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
ZIP := dist/$(NAME)-$(VERSION).zip
# Signed with the "ThockBox Signing" identity when this Mac has it (see
# `make signing-cert`), so the Accessibility grant survives rebuilds and
# updates. Otherwise ad-hoc ("-"), where every rebuild needs a new grant.
CODESIGN_ID ?= $(or $(shell security find-identity -p codesigning 2>/dev/null | awk -F'"' '/"ThockBox Signing"/ {split($$1, a, " "); print a[2]; exit}'),-)

.PHONY: all build bundle zip release cask signing-cert test bench sounds icon clean run

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
	scripts/build_intents_metadata.sh $(BUNDLE)
	codesign --force --sign "$(CODESIGN_ID)" $(BUNDLE)
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

# Publish the zip as GitHub release v<version>. The app's updater looks for
# the newest release and its ThockBox-<version>.zip asset.
release: zip cask
	@if [ "$(CODESIGN_ID)" = "-" ]; then echo "refusing to release an ad-hoc build; run 'make signing-cert'"; exit 1; fi
	gh release create v$(VERSION) $(ZIP) --title "ThockBox $(VERSION)" --generate-notes
	@echo "Now copy packaging/thockbox.rb to Casks/thockbox.rb in Bruno-Alumn/homebrew-thockbox."

# Point the Homebrew cask (packaging/thockbox.rb) at this version's zip.
cask: zip
	scripts/update_cask.sh $(VERSION) $(ZIP)

clean:
	rm -rf .build dist/$(NAME).app dist/$(NAME)-*.zip
