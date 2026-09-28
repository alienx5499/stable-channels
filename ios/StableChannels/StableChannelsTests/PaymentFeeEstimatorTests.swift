import XCTest
@testable import StableChannels

final class PaymentFeeEstimatorTests: XCTestCase {
    // MARK: - Lightning Routing Fee Tests

    func testEstimateLightningFee_zeroSatsReturnsZero() {
        let fee = PaymentFeeEstimator.estimateLightningFee(
            sats: 0,
            baseMsat: 1_000,
            proportionalMillionths: 500
        )
        XCTAssertEqual(fee, 0)
    }

    func testEstimateLightningFee_standardForwardingCalculation() {
        // 10,000 sats = 10,000,000 msat
        // proportional: 10,000,000 * 500 / 1,000,000 = 5,000 msat
        // total: 1,000 base + 5,000 prop = 6,000 msat = 6 sats
        let fee = PaymentFeeEstimator.estimateLightningFee(
            sats: 10_000,
            baseMsat: 1_000,
            proportionalMillionths: 500
        )
        XCTAssertEqual(fee, 6)
    }

    func testEstimateLightningFee_ceilingDivisionRoundsUp() {
        // 1 sat = 1,000 msat. 1 msat base, 0 ppm -> 1 msat -> rounds up to 1 sat
        let fee = PaymentFeeEstimator.estimateLightningFee(
            sats: 1,
            baseMsat: 1,
            proportionalMillionths: 0
        )
        XCTAssertEqual(fee, 1)
    }

    func testEstimateLightningFee_overflowSafetyDoesNotCrash() {
        let fee = PaymentFeeEstimator.estimateLightningFee(
            sats: UInt64.max,
            baseMsat: 1_000,
            proportionalMillionths: 5_000
        )
        XCTAssertGreaterThan(fee, 0)
    }

    // MARK: - Onchain Fee Estimation Tests

    func testEstimateOnchainFee_standardSendUses140VBytes() {
        let fee = PaymentFeeEstimator.estimateOnchainFee(feeRateSatVb: 10, isSendAll: false)
        XCTAssertEqual(fee, 1_400)
    }

    func testEstimateOnchainFee_sendAllUses110VBytes() {
        let fee = PaymentFeeEstimator.estimateOnchainFee(feeRateSatVb: 10, isSendAll: true)
        XCTAssertEqual(fee, 1_100)
    }

    func testEstimateOnchainFee_customVBytes() {
        let fee = PaymentFeeEstimator.estimateOnchainFee(
            feeRateSatVb: 12,
            isSendAll: false,
            sendVBytes: 250
        )
        XCTAssertEqual(fee, 3_000)
    }

    func testEstimateOnchainFee_overflowSafety() {
        let fee = PaymentFeeEstimator.estimateOnchainFee(feeRateSatVb: UInt64.max, isSendAll: false)
        XCTAssertEqual(fee, UInt64.max)
    }

    // MARK: - Network Fee Speed Tier Tests

    func testNetworkFeeSpeedTier_standardBaseline() {
        let base: UInt64 = 10
        XCTAssertEqual(NetworkFeeSpeedTier.economy.effectiveRate(baseRate: base), 7)
        XCTAssertEqual(NetworkFeeSpeedTier.standard.effectiveRate(baseRate: base), 10)
        XCTAssertEqual(NetworkFeeSpeedTier.priority.effectiveRate(baseRate: base), 14)
    }

    func testNetworkFeeSpeedTier_lowFeeMempool() {
        let base: UInt64 = 1
        XCTAssertEqual(NetworkFeeSpeedTier.economy.effectiveRate(baseRate: base), 1)
        XCTAssertEqual(NetworkFeeSpeedTier.standard.effectiveRate(baseRate: base), 1)
        XCTAssertEqual(NetworkFeeSpeedTier.priority.effectiveRate(baseRate: base), 2)
    }

    func testNetworkFeeSpeedTier_congestedMempool() {
        let base: UInt64 = 50
        XCTAssertEqual(NetworkFeeSpeedTier.economy.effectiveRate(baseRate: base), 35)
        XCTAssertEqual(NetworkFeeSpeedTier.standard.effectiveRate(baseRate: base), 50)
        XCTAssertEqual(NetworkFeeSpeedTier.priority.effectiveRate(baseRate: base), 70)
    }

    func testNetworkFeeSpeedTier_monotonicityAcrossRange() {
        for rate: UInt64 in 1...200 {
            let eco = NetworkFeeSpeedTier.economy.effectiveRate(baseRate: rate)
            let std = NetworkFeeSpeedTier.standard.effectiveRate(baseRate: rate)
            let pri = NetworkFeeSpeedTier.priority.effectiveRate(baseRate: rate)

            XCTAssertGreaterThanOrEqual(eco, 1, "Economy must never drop below 1 sat/vB")
            XCTAssertLessThanOrEqual(eco, std, "Economy must not exceed standard")
            XCTAssertGreaterThan(pri, std, "Priority must strictly exceed standard")
        }
    }

    func testNetworkFeeSpeedTier_metadataFields() {
        for tier in NetworkFeeSpeedTier.allCases {
            XCTAssertFalse(tier.title.isEmpty)
            XCTAssertFalse(tier.estimatedTime.isEmpty)
            XCTAssertFalse(tier.targetBlocks.isEmpty)
            XCTAssertEqual(tier.id, tier.rawValue)
        }
    }

    // MARK: - Curve Geometry & Lemniscate Tests

    func testCurveProgressIndicator_parametricCurvesAreFiniteAndBounded() {
        for curve in CurveProgressIndicator.CurveType.allCases {
            for step in 0...20 {
                let progress = Double(step) / 20.0
                let pt = CurveProgressIndicator.pointOnCurve(curve: curve, progress: progress, detailScale: 1.0)
                XCTAssertTrue(pt.x.isFinite, "Curve \(curve) point x must be finite at progress \(progress)")
                XCTAssertTrue(pt.y.isFinite, "Curve \(curve) point y must be finite at progress \(progress)")
                XCTAssertGreaterThanOrEqual(pt.x, -50.0)
                XCTAssertLessThanOrEqual(pt.x, 150.0)
                XCTAssertGreaterThanOrEqual(pt.y, -50.0)
                XCTAssertLessThanOrEqual(pt.y, 150.0)
            }
        }
    }

    func testLemniscateShape_createsValidBoundedPath() {
        let shape = LemniscateShape()
        let rect = CGRect(x: 0, y: 0, width: 100, height: 60)
        let path = shape.path(in: rect)
        let bounds = path.boundingRect

        XCTAssertFalse(bounds.isNull)
        XCTAssertFalse(bounds.isEmpty)
        XCTAssertGreaterThan(bounds.width, 0)
        XCTAssertGreaterThan(bounds.height, 0)
        XCTAssertLessThanOrEqual(bounds.maxX, rect.maxX + 1.0)
        XCTAssertGreaterThanOrEqual(bounds.minX, rect.minX - 1.0)
    }
}
