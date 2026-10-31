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

    func testRecipesUseSafeDetailFrameCounts() {
        XCTAssertTrue(CameraRecipe.builtIns.allSatisfy { (4...30).contains($0.detailFrames) })
    }
}
