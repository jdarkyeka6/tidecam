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

    func testRecipesUseSafeDetailFrameCounts() {
        XCTAssertTrue(CameraRecipe.builtIns.allSatisfy { (4...30).contains($0.detailFrames) })
    }
}
