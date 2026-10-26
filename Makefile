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

.PHONY: check build unused analyze test snapshots coverage format lint layers density nesting \
	self-test plist \
	perf-baseline perf-compare validation

check: build unused analyze test snapshots format lint layers density nesting self-test plist
	@echo "All checks passed."

# BUILD-01, BUILD-02: the targets treat warnings as errors. Swift 6 keeps some diagnostics of
# imported C and Objective-C APIs as warnings that -warnings-as-errors does not raise (D-132).
# The build thus starts in a fresh folder, so that each file compiles and prints its warnings,
# and it fails on each warning line, as `make analyze` does. The test bundle builds there too,
# because BUILD-02 covers each target.
CLEAN_BUILD := .build/CleanBuild
build:
	@rm -rf $(CLEAN_BUILD)
	@mkdir -p $(CLEAN_BUILD)
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(CLEAN_BUILD) \
		-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build \
		> $(CLEAN_BUILD)/build.log 2>&1 || { cat $(CLEAN_BUILD)/build.log; exit 1; }
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(CLEAN_BUILD) \
		-destination 'generic/platform=iOS' -configuration Release CODE_SIGNING_ALLOWED=NO \
		ENABLE_TESTABILITY=YES build-for-testing > $(CLEAN_BUILD)/test-build.log 2>&1 \
		|| { cat $(CLEAN_BUILD)/test-build.log; exit 1; }
	@if grep -E '^/.*: warning:' $(CLEAN_BUILD)/build.log $(CLEAN_BUILD)/test-build.log; then \
		echo "Build warnings above (BUILD-02, D-132)."; exit 1; fi
	@echo "build: 0 warnings in the app and the test bundle"

# SCOPE-01: no declaration without a reader (D-174). The SwiftLint analyzer rule
# unused_declaration reads the compiler log of the clean build of `make build`. A declaration that
# only the tests or the shaders read has a local exception with the reason.
unused: build
	swiftlint analyze --strict --quiet --compiler-log-path $(CLEAN_BUILD)/build.log
	@echo "unused: 0 findings"

# BUILD-04: zero analyzer findings.
analyze:
	@mkdir -p $(DERIVED_DATA)
	@$(XCODEBUILD) -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO analyze \
		> $(DERIVED_DATA)/analyze.log 2>&1 || { cat $(DERIVED_DATA)/analyze.log; exit 1; }
	@if grep -E '^/.*: (warning|error):' $(DERIVED_DATA)/analyze.log; then \
		echo "Analyzer findings above."; exit 1; fi
	@echo "analyze: 0 findings"

# Tier A tests run on the Mac. Package tests cannot run on a device, so the tests of the other
# packages run in PointerDeviceTests on the iPad (D-77). The UI tests of PointerUITests run on the
# iPad after them, each in a new process of the app on a temporary library (D-178). Keep the iPad
# unlocked during the run.
test:
	@for package in $(TIER_A); do \
		if [ -d Packages/$$package/Tests ]; then \
			swift test --package-path Packages/$$package || exit 1; \
		fi; \
	done
	$(DEVICE_TEST) -quiet -only-testing:PointerDeviceTests -only-testing:PointerUITests
	@echo "test: done"

# TEST-07: the snapshot tests run in PointerDeviceTests on the iPad and compare against the
# reference images in the test bundle (D-77).
snapshots:
	$(DEVICE_TEST) -quiet \
		-only-testing:PointerDeviceTests/InkImageTests \
		-only-testing:PointerDeviceTests/RedrawTests \
		-only-testing:PointerDeviceTests/EraserMaskTests \
		-only-testing:PointerDeviceTests/WorkspaceSelectorSnapshotTests \
		-only-testing:PointerDeviceTests/LargeTextSnapshotTests \
		-only-testing:PointerDeviceTests/LargeTextChromeSnapshotTests \
		-only-testing:PointerDeviceTests/HistoryButtonsSnapshotTests \
		-only-testing:PointerDeviceTests/ToolControlsSnapshotTests \
		-only-testing:PointerDeviceTests/TextRenderingTests \
		-only-testing:PointerDeviceTests/TextAlignmentSnapshotTests \
		-only-testing:PointerDeviceTests/CardRenderingTests \
		-only-testing:PointerDeviceTests/PreviewRenderTests \
		-only-testing:PointerDeviceTests/TransitionTests \
		-only-testing:PointerDeviceTests/UpButtonSnapshotTests \
		-only-testing:PointerDeviceTests/CardMenuSnapshotTests \
		-only-testing:PointerDeviceTests/HoverDotSnapshotTests \
		-only-testing:PointerDeviceTests/PDFSnapshotTests \
		-only-testing:PointerDeviceTests/BackupFeatureSnapshotTests
	@echo "snapshots: done"

# TEST-02, D-120: the line coverage of the Tier A packages and of Rendering and Export. The device run builds
# with coverage flags into a derived data folder of its own, so the Release build of `make test`
# stays. The instrumented code is slower, so the target ignores the test failures of that run, and
# its measures do not count. `make test` runs the tests. Keep the iPad unlocked during the run.
COVERAGE_DATA := .build/CoverageData
COVERAGE_REPORTS := .build/Coverage
COVERAGE_FRAMEWORKS := $(COVERAGE_DATA)/Build/Products/Release-iphoneos/Pointer.app/Frameworks
coverage:
	@rm -rf $(COVERAGE_REPORTS) $(COVERAGE_DATA)/Build/ProfileData
	@mkdir -p $(COVERAGE_REPORTS)
	@for package in $(TIER_A); do \
		swift test --package-path Packages/$$package --enable-code-coverage || exit 1; \
		cp "$$(swift test --package-path Packages/$$package --show-codecov-path)" \
			$(COVERAGE_REPORTS)/$$package.json || exit 1; \
	done
	-xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'id=$(DEVICE)' -derivedDataPath $(COVERAGE_DATA) -allowProvisioningUpdates \
		ENABLE_TESTABILITY=YES -enableCodeCoverage YES \
		OTHER_SWIFT_FLAGS='$$(inherited) -profile-generate -profile-coverage-mapping' \
		-quiet -only-testing:PointerDeviceTests
	@for package in Rendering Export; do \
		framework=$$(ls -d $(COVERAGE_FRAMEWORKS)/$${package}_*_PackageProduct.framework) && \
		xcrun llvm-cov export "$$framework/$$(basename "$$framework" .framework)" -summary-only \
			-instr-profile $(COVERAGE_DATA)/Build/ProfileData/$(DEVICE)/Coverage.profdata \
			> $(COVERAGE_REPORTS)/$$package.json || exit 1; \
	done
	swift Scripts/coverage.swift --root .build --allow Scripts/coverage-allow.txt

# D-172, D-177: the performance suites alone, each run in a new test process. `make perf-baseline`
# records the baseline of the iPad model. `make perf-compare` fails if a time is more than 10 %
# worse with p < 0.01. With p from 0.01 to 0.05 it adds 10 runs and compares again. A memory peak
# and a count are recorded without a gate. 10 runs take about 50 minutes. Keep the iPad unlocked.
PERF_RUNS := 10
PERF_SUITES := CanvasOpenPerformanceTests CanvasMemoryPerformanceTests \
	TransitionMemoryPerformanceTests EraseUndoPerformanceTests TextHitTestPerformanceTests \
	EraserFramePerformanceTests FrameLoopTests RenderingPerformanceTests \
	LevelOfDetailPerformanceTests PointArenaPerformanceTests TextPassPerformanceTests \
	TextLayoutPerformanceTests PreviewMakerPerformanceTests PreviewsAfterRestoreTests \
	StrokeStoreMemoryTests BackupBudgetTests SnapshotPerformanceTests \
	LibrarySavePerformanceTests DeviceStatePerformanceTests SQLiteSpeedTests \
	ExportPerformanceTests OpenAnimationTests FlightStallTests CanvasLifetimeTests \
	TextBuildPerformanceTests GlyphInsertPerformanceTests
PERF_BASELINE := Performance/Baselines/iPad16,4.json
perf-baseline:
	Scripts/perf-runs.sh baseline 1 $(PERF_RUNS) $(DEVICE) $(PERF_SUITES)
	xcrun devicectl device info details --device $(DEVICE) --json-output .build/Perf/device.json \
		> /dev/null
	swift Scripts/perf.swift record --output $(PERF_BASELINE) --commit "$$(git rev-parse --short HEAD)" \
		--device "$$(plutil -extract result.hardwareProperties.productType raw .build/Perf/device.json)" \
		--os "$$(plutil -extract result.deviceProperties.osVersionNumber raw .build/Perf/device.json)" \
		--xcode "$$(xcodebuild -version | head -1)" \
		$$(for run in $$(seq 1 $(PERF_RUNS)); do printf '.build/Perf/baseline-%s.xcresult ' $$run; done)

perf-compare:
	Scripts/perf-runs.sh compare 1 $(PERF_RUNS) $(DEVICE) $(PERF_SUITES)
	@swift Scripts/perf.swift compare --baseline $(PERF_BASELINE) .build/Perf/compare-*.xcresult; \
	status=$$?; \
	if [ $$status -eq 3 ]; then \
		echo "p from 0.01 to 0.05: 10 more runs (D-177)"; \
		Scripts/perf-runs.sh compare $$(($(PERF_RUNS) + 1)) $$((2 * $(PERF_RUNS))) $(DEVICE) \
			$(PERF_SUITES) || exit 1; \
		swift Scripts/perf.swift compare --baseline $(PERF_BASELINE) \
			.build/Perf/compare-*.xcresult; status=$$?; \
	fi; \
	exit $$status

# D-186: PointerDeviceTests with Metal API validation and shader validation. Each validation error
# stops the test. Validation adds allocations to each frame and slows the GPU, so the allocation
# suites and the performance suites do not run here. Run it at each close of a milestone and for
# each change of the render code. Keep the iPad unlocked during the run.
ALLOCATION_SUITES := EditAllocationTests EraserSampleAllocationTests FrameAllocationTests \
	GridAllocationTests HoverSampleAllocationTests PreviewAllocationTests \
	TextEditFrameAllocationTests TextMoveAllocationTests TextPassAllocationTests \
	TransitionAllocationTests ZoomFrameAllocationTests FrameKindAllocationTests \
	DragPostAllocationTests GestureAllocationTests
validation:
	TEST_RUNNER_MTL_DEBUG_LAYER=1 TEST_RUNNER_MTL_SHADER_VALIDATION=1 $(DEVICE_TEST) -quiet \
		-only-testing:PointerDeviceTests \
		$(foreach suite,$(ALLOCATION_SUITES) $(PERF_SUITES),-skip-testing:PointerDeviceTests/$(suite))
	@echo "validation: done"

# STYLE-04. The fixtures hold deliberate violations, so the formatter skips them.
format:
	swift format lint --strict --recursive PointerApp PointerAppTests PointerUITests Packages Scripts/*.swift \
		Scripts/Nesting/Package.swift Scripts/Nesting/Sources

lint:
	swiftlint --strict --quiet

# ARCH-02, BUILD-03
layers:
	swift Scripts/check-layers.swift

# CONTRACT-02
density:
	swift Scripts/assertion-density.swift

# FLOW-04: at most 3 levels of control flow in a function body (D-174, D-175). A SwiftSyntax tool
# under D-04. The first build takes about 2 minutes, later runs reuse it.
NESTING := Scripts/Nesting/.build/release/Nesting
nesting:
	swift build -c release --package-path Scripts/Nesting --quiet
	$(NESTING) --root .

# The check scripts and the SwiftLint rules on Scripts/Fixtures.
self-test:
	Scripts/self-test.sh

# STO-02, STO-03: the Files app shows Documents/ only with both keys set to true.
# D-156: the document picker of a restore shows only files of the snapshot type.
SNAPSHOT_TYPE := UTImportedTypeDeclarations.0
plist:
	plutil -extract UIFileSharingEnabled raw PointerApp/Info.plist | grep -qx true
	plutil -extract LSSupportsOpeningDocumentsInPlace raw PointerApp/Info.plist | grep -qx true
	plutil -extract $(SNAPSHOT_TYPE).UTTypeIdentifier raw PointerApp/Info.plist \
		| grep -qx dk.saarikivi.pointer.snapshot
	plutil -extract $(SNAPSHOT_TYPE).UTTypeTagSpecification json -o - PointerApp/Info.plist \
		| grep -q '"public.filename-extension":\["sqlite"\]'
	plutil -extract $(SNAPSHOT_TYPE).UTTypeConformsTo json -o - PointerApp/Info.plist \
		| grep -q '"public.database"'
	plutil -extract $(SNAPSHOT_TYPE).UTTypeConformsTo json -o - PointerApp/Info.plist \
		| grep -q '"public.data"'
	@echo "plist: Files app keys and the snapshot type present"
