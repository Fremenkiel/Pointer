# One target per check of the pull request checklist (docs/code-of-code.md section 5).
# `make check` runs all of them.

PROJECT := Pointer.xcodeproj
SCHEME := PointerApp
DERIVED_DATA := .build/DerivedData
# The connected iPad. Learned rule 1 of AGENTS.md bans the simulator (D-77).
DEVICE ?= 00008132-000018993E8B801C
DEVICE_DATA := .build/DeviceData
TIER_A := Geometry Model InkEngine Persistence
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED_DATA)
# Device runs use Release, as the performance tests need (PERF-03).
DEVICE_TEST := xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
	-destination 'id=$(DEVICE)' -derivedDataPath $(DEVICE_DATA) -allowProvisioningUpdates \
	ENABLE_TESTABILITY=YES

.PHONY: check build analyze test snapshots format lint layers density self-test plist

check: build analyze test snapshots format lint layers density self-test plist
	@echo "All checks passed."

# BUILD-01, BUILD-02: the targets treat warnings as errors.
build:
	$(XCODEBUILD) -destination 'generic/platform=iOS' -quiet CODE_SIGNING_ALLOWED=NO build

# BUILD-04: zero analyzer findings.
analyze:
	@mkdir -p $(DERIVED_DATA)
	@$(XCODEBUILD) -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO analyze \
		> $(DERIVED_DATA)/analyze.log 2>&1 || { cat $(DERIVED_DATA)/analyze.log; exit 1; }
	@if grep -E '^/.*: (warning|error):' $(DERIVED_DATA)/analyze.log; then \
		echo "Analyzer findings above."; exit 1; fi
	@echo "analyze: 0 findings"

# Tier A tests run on the Mac. Package tests cannot run on a device, so the tests of the other
# packages run in PointerDeviceTests on the iPad (D-77). Keep the iPad unlocked during the run.
test:
	@for package in $(TIER_A); do \
		if [ -d Packages/$$package/Tests ]; then \
			swift test --package-path Packages/$$package || exit 1; \
		fi; \
	done
	$(DEVICE_TEST) -quiet -only-testing:PointerDeviceTests
	@echo "test: done"

# TEST-07: the snapshot tests run in PointerDeviceTests on the iPad and compare against the
# reference images in the test bundle (D-77).
snapshots:
	$(DEVICE_TEST) -quiet \
		-only-testing:PointerDeviceTests/InkImageTests \
		-only-testing:PointerDeviceTests/RedrawTests \
		-only-testing:PointerDeviceTests/EraserMaskTests \
		-only-testing:PointerDeviceTests/WorkspaceSelectorSnapshotTests \
		-only-testing:PointerDeviceTests/HistoryButtonsSnapshotTests \
		-only-testing:PointerDeviceTests/ToolControlsSnapshotTests \
		-only-testing:PointerDeviceTests/TextRenderingTests \
		-only-testing:PointerDeviceTests/TextAlignmentSnapshotTests \
		-only-testing:PointerDeviceTests/CardRenderingTests \
		-only-testing:PointerDeviceTests/PreviewRenderTests \
		-only-testing:PointerDeviceTests/TransitionTests \
		-only-testing:PointerDeviceTests/UpButtonSnapshotTests \
		-only-testing:PointerDeviceTests/CardMenuSnapshotTests
	@echo "snapshots: done"

# STYLE-04. The fixtures hold deliberate violations, so the formatter skips them.
format:
	swift format lint --strict --recursive PointerApp PointerAppTests Packages Scripts/*.swift

lint:
	swiftlint --strict --quiet

# ARCH-02, BUILD-03
layers:
	swift Scripts/check-layers.swift

# CONTRACT-02
density:
	swift Scripts/assertion-density.swift

# The check scripts and the SwiftLint rules on Scripts/Fixtures.
self-test:
	Scripts/self-test.sh

# STO-02, STO-03: the Files app shows Documents/ only with both keys set to true.
plist:
	plutil -extract UIFileSharingEnabled raw PointerApp/Info.plist | grep -qx true
	plutil -extract LSSupportsOpeningDocumentsInPlace raw PointerApp/Info.plist | grep -qx true
	@echo "plist: Files app keys present"
