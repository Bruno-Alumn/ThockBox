APP := Thockbox
BUILD := .build/release
BUNDLE := dist/$(APP).app
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
ZIP := dist/$(APP)-$(VERSION).zip
# Ad-hoc by default. With "-", every rebuild changes the binary hash and
# invalidates the Accessibility grant (see README). Set a real identity to
# keep the grant across rebuilds.
CODESIGN_ID ?= -

.PHONY: all build bundle zip test bench sounds icon clean run

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
	codesign --force --sign "$(CODESIGN_ID)" $(BUNDLE)
	@du -sh $(BUNDLE)
	@echo "note: if this replaced an already-granted build, re-grant Accessibility:"
	@echo "  tccutil reset Accessibility io.github.bruno-alumn.thockbox && open $(BUNDLE)"

# Rebuild the sound catalog from upstream sources (requires uv + network).
sounds:
	uv run --with soundfile,numpy scripts/build_sounds.py

# Re-render Resources/AppIcon.icns from scripts/make_icon.swift.
icon:
	swift scripts/make_icon.swift Resources/AppIcon.icns

# Unit tests, then a headless audio smoke test that decodes and plays every pack.
test: bundle
	swift test
	$(BUNDLE)/Contents/MacOS/$(APP) --test-audio

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

clean:
	rm -rf .build dist/$(APP).app dist/$(APP)-*.zip
