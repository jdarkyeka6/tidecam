import XCTest
@testable import TideCam

final class DetailProcessorTests: XCTestCase {
    func testEmptyBurstProducesNoCandidate() {
        XCTAssertNil(DetailProcessor().bestCandidate(from: []))
    }

    func testInvalidDataIsIgnored() {
        XCTAssertNil(DetailProcessor().bestCandidate(from: [Data([0x00, 0x01, 0x02])]))
    }

    func testZoomEnhancerDoesNotModifyInvalidOrUnzoomedData() {
        let data = Data([0x00, 0x01, 0x02])
        let enhancer = ZoomEnhancer()
        XCTAssertNil(enhancer.enhance(data, zoomFactor: 2))
        XCTAssertNil(enhancer.enhance(data, zoomFactor: 1))
    }

    func testFusionRejectsMissingAndInvalidFrames() {
        let fusion = MultiFrameFusion()
        XCTAssertNil(fusion.fuse(reference: Data(), alternatives: [Data([0x01])]))
        XCTAssertNil(fusion.fuse(reference: Data([0x01]), alternatives: []))
    }

    func testRankedFramesIgnoreInvalidData() {
        let scorer = DetailProcessor()
        XCTAssertTrue(scorer.rankedFrames(from: [Data([0x00])]).isEmpty)
        XCTAssertNil(scorer.bestCandidate(from: []))
    }

    func testFaceEnhancerRejectsInvalidPhotos() {
        XCTAssertNil(FaceEnhancer().enhance(Data([0x00, 0x01, 0x02])))
    }

    func testVideoQualityProfilesAreCorrect() {
        XCTAssertEqual(VideoQuality.uhd60.width, 3840)
        XCTAssertEqual(VideoQuality.uhd60.height, 2160)
        XCTAssertEqual(VideoQuality.uhd60.fps, 60)
        XCTAssertEqual(VideoQuality.fhd30.width, 1920)
        XCTAssertEqual(VideoQuality.fhd30.fps, 30)
        XCTAssertEqual(VideoQuality.allCases.count, 4)
    }

    func testRecordingRecoveryMovesVideoIntoLibrary() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("tidecam-backup-test-\(UUID().uuidString).mov")
        let bytes = Data([0x00, 0x01, 0x02, 0x03])
        try bytes.write(to: source)
        let destination = try TideCamLibraryStorage.moveFile(from: source)
        defer { try? FileManager.default.removeItem(at: destination) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
        XCTAssertEqual(destination.pathExtension, "mov")
    }

    func testBurstSamplingCoversBeginningMiddleAndEnd() {
        let indices = BurstHighlightPicker.sampleIndices(total: 200, limit: 36)
        XCTAssertEqual(indices.count, 36)
        XCTAssertEqual(indices.first, 0)
        XCTAssertEqual(indices.last, 199)
        XCTAssertEqual(Set(indices).count, indices.count)
        XCTAssertEqual(indices, indices.sorted())
    }

    func testBurstSamplingHandlesShortAndEmptySessions() {
        XCTAssertEqual(BurstHighlightPicker.sampleIndices(total: 0), [])
        XCTAssertEqual(BurstHighlightPicker.sampleIndices(total: 5, limit: 10), [0, 1, 2, 3, 4])
        XCTAssertEqual(BurstHighlightPicker.sampleIndices(total: 100, limit: 1), [0])
        XCTAssertEqual(BurstHighlightPicker.sampleIndices(total: 10, limit: 0), [])
    }

    func testBurstBestShotIgnoresUnreadableFiles() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-burst-\(UUID().uuidString).heic")
        XCTAssertNil(BurstHighlightPicker().select(from: []))
        XCTAssertNil(BurstHighlightPicker().select(from: [missing]))
    }

    func testBurstModesKeepCaptureConcurrencyBounded() {
        XCTAssertEqual(BurstMode.fast.inFlightLimit, 3)
        XCTAssertEqual(BurstMode.balanced.inFlightLimit, 2)
    }

    func testRecipesUseSafeDetailFrameCounts() {
        XCTAssertTrue(CameraRecipe.builtIns.allSatisfy { (4...30).contains($0.detailFrames) })
    }
}
