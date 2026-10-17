# One target per check of the pull request checklist (docs/code-of-code.md section 5).
# `make check` runs all of them.

PROJECT := Pointer.xcodeproj
SCHEME := PointerApp
DERIVED_DATA := .build/DerivedData
SIMULATOR ?= platform=iOS Simulator,name=iPad Pro 13-inch (M5)
TIER_A := Geometry Model InkEngine Persistence
OTHER_PACKAGES := Rendering Export DesignSystem CanvasFeature WorkspaceFeature BackupFeature
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED_DATA)

.PHONY: check build analyze test format lint layers density self-test

check: build analyze test format lint layers density self-test
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

# Tier A tests run on the Mac. Other package tests run on an iPad simulator.
# A package without a Tests folder has no tests yet.
test:
	@for package in $(TIER_A); do \
		if [ -d Packages/$$package/Tests ]; then \
			swift test --package-path Packages/$$package || exit 1; \
		fi; \
	done
	@for package in $(OTHER_PACKAGES); do \
		if [ -d Packages/$$package/Tests ]; then \
			(cd Packages/$$package && xcodebuild test -scheme $$package \
				-destination '$(SIMULATOR)' -quiet) || exit 1; \
		fi; \
	done
	@echo "test: done"

# STYLE-04. The fixtures hold deliberate violations, so the formatter skips them.
format:
	swift format lint --strict --recursive PointerApp Packages Scripts/*.swift

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
