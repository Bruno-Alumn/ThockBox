APP := Thockbox
BUILD := .build/release
BUNDLE := dist/$(APP).app
# Ad-hoc by default. With "-", every rebuild changes the binary hash and
# invalidates the Accessibility grant (see README). Set a real identity to
# keep the grant across rebuilds.
CODESIGN_ID ?= -

.PHONY: all build bundle test sounds icon clean run

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

run: bundle
	open $(BUNDLE)

clean:
	rm -rf .build dist/$(APP).app
