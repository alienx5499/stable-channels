import Foundation

/// Multi-tier recommended fee rates (sat/vB) matching target confirmation block conventions.
struct RecommendedFees: Codable, Equatable, Sendable {
    let fastestFee: UInt64
    let halfHourFee: UInt64
    let hourFee: UInt64
    let minimumFee: UInt64

    func rate(for tier: NetworkFeeSpeedTier) -> UInt64 {
        switch tier {
        case .priority:
            return max(1, fastestFee)
        case .standard:
            return max(1, halfHourFee)
        case .economy:
            return max(minimumFee, hourFee)
        }
    }

    static let `default` = RecommendedFees(
        fastestFee: 15,
        halfHourFee: 10,
        hourFee: 8,
        minimumFee: 1
    )

    init(fastestFee: UInt64, halfHourFee: UInt64, hourFee: UInt64, minimumFee: UInt64) {
        self.fastestFee = fastestFee
        self.halfHourFee = halfHourFee
        self.hourFee = hourFee
        self.minimumFee = minimumFee
    }

    init(wsFees: MempoolWSFees) {
        self.init(
            fastestFee: wsFees.fastestFee,
            halfHourFee: wsFees.halfHourFee,
            hourFee: wsFees.hourFee,
            minimumFee: wsFees.minimumFee
        )
    }
}

/// Single source of fee-rate truth. Strategy-per-source, parallel fetch, async cache.
protocol FeeRateSource: Sendable {
    /// Fetch 6-block target rate (sat/vB). Throws on timeout/network/parse.
    func fetchRate() async throws -> UInt64
    /// Fetch full multi-tier recommended fee structure.
    func fetchRecommendedFees() async throws -> RecommendedFees
}

extension FeeRateSource {
    func fetchRecommendedFees() async throws -> RecommendedFees {
        let rate = try await fetchRate()
        return RecommendedFees(
            fastestFee: max(1, (rate * 13) / 10),
            halfHourFee: rate,
            hourFee: max(1, (rate * 8) / 10),
            minimumFee: max(1, rate / 2)
        )
    }
}

/// Blockstream esplora `{"1": ..., "3": ..., "6": ..., "144": ...}`
struct BlockstreamFeeSource: FeeRateSource {
    let baseURL: URL
    let timeout: TimeInterval

    func fetchRate() async throws -> UInt64 {
        let rec = try await fetchRecommendedFees()
        return rec.halfHourFee
    }

    func fetchRecommendedFees() async throws -> RecommendedFees {
        let url = baseURL.appendingPathComponent("fee-estimates")
        let data = try await Self.fetch(url: url, timeout: timeout)
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw FeeRateError.parseFailed(source: "blockstream") }

        let block1 = (json["1"] as? Double) ?? (json["2"] as? Double) ?? 15.0
        let block3 = (json["3"] as? Double) ?? (json["4"] as? Double) ?? 10.0
        let block6 = (json["6"] as? Double) ?? 8.0
        let minFee = (json["144"] as? Double) ?? 1.0

        return RecommendedFees(
            fastestFee: UInt64(block1.rounded(.up)),
            halfHourFee: UInt64(block3.rounded(.up)),
            hourFee: UInt64(block6.rounded(.up)),
            minimumFee: max(1, UInt64(minFee.rounded(.up)))
        )
    }
}

/// Mempool v1 `/api/v1/fees/recommended` — `{fastestFee, halfHourFee, hourFee, minimumFee}`.
struct MempoolV1FeeSource: FeeRateSource {
    let baseURL: URL
    let timeout: TimeInterval

    func fetchRate() async throws -> UInt64 {
        let rec = try await fetchRecommendedFees()
        return rec.halfHourFee
    }

    func fetchRecommendedFees() async throws -> RecommendedFees {
        let url = baseURL.appendingPathComponent("api/v1/fees/recommended")
        let data = try await Self.fetch(url: url, timeout: timeout)
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let fastest = json["fastestFee"] as? Double,
            let halfHour = json["halfHourFee"] as? Double,
            let hour = json["hourFee"] as? Double,
            let min = json["minimumFee"] as? Double
        else { throw FeeRateError.parseFailed(source: "mempool-v1") }

        return RecommendedFees(
            fastestFee: UInt64(fastest.rounded(.up)),
            halfHourFee: UInt64(halfHour.rounded(.up)),
            hourFee: UInt64(hour.rounded(.up)),
            minimumFee: max(1, UInt64(min.rounded(.up)))
        )
    }
}

enum FeeRateError: Error {
    case timeout
    case http(Int)
    case parseFailed(source: String)
    case network(Error)
}

extension FeeRateSource {
    /// Shared async fetch with hard timeout. Returns Data on 200, throws otherwise.
    static func fetch(url: URL, timeout: TimeInterval) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw FeeRateError.http(-1)
            }
            guard http.statusCode == 200 else {
                throw FeeRateError.http(http.statusCode)
            }
            return data
        } catch let err as FeeRateError {
            throw err
        } catch let err as URLError where err.code == .timedOut {
            throw FeeRateError.timeout
        } catch {
            throw FeeRateError.network(error)
        }
    }
}

/// Off-main cache + in-flight dedup. Sources fetched in parallel; first success wins.
actor FeeRateCache {
    private let sources: [FeeRateSource]
    private let cacheTTL: Duration
    private let fallback: UInt64
    private var cachedRate: UInt64?
    private var cachedRecommendedFees: RecommendedFees?
    private var cachedAt: ContinuousClock.Instant?
    private var inFlight: Task<RecommendedFees, Never>?

    init(
        sources: [FeeRateSource],
        cacheTTL: Duration = .seconds(60),
        fallback: UInt64 = 2
    ) {
        self.sources = sources
        self.cacheTTL = cacheTTL
        self.fallback = fallback
    }

    func updateRecommendedFees(_ fees: RecommendedFees) {
        cachedRecommendedFees = fees
        cachedRate = fees.halfHourFee
        cachedAt = ContinuousClock.now
    }

    /// Returns multi-tier recommended fees. Coalesces concurrent network requests.
    func recommendedFees() async -> RecommendedFees {
        if let rec = cachedRecommendedFees,
           let at = cachedAt,
           ContinuousClock.now - at < cacheTTL {
            return rec
        }
        if let task = inFlight {
            return await task.value
        }
        let task = Task { [sources, fallback] () -> RecommendedFees in
            await withTaskGroup(of: RecommendedFees?.self, returning: RecommendedFees.self) { group in
                for source in sources {
                    group.addTask {
                        do {
                            return try await source.fetchRecommendedFees()
                        } catch {
                            return nil
                        }
                    }
                }
                for await fees in group {
                    if let fees {
                        group.cancelAll()
                        return fees
                    }
                }
                return RecommendedFees(
                    fastestFee: max(1, (fallback * 13) / 10),
                    halfHourFee: fallback,
                    hourFee: max(1, (fallback * 8) / 10),
                    minimumFee: max(1, fallback / 2)
                )
            }
        }
        inFlight = task
        let fees = await task.value
        inFlight = nil
        cachedRecommendedFees = fees
        cachedRate = fees.halfHourFee
        cachedAt = ContinuousClock.now
        return fees
    }

    func currentRate() async -> UInt64 {
        let fees = await recommendedFees()
        return fees.halfHourFee
    }

    func invalidate() {
        cachedRate = nil
        cachedRecommendedFees = nil
        cachedAt = nil
    }
}

/// Public façade. Caller-friendly; defers to cache actor for all state.
final class FeeRateService: Sendable {
    private let cache: FeeRateCache

    init(
        sources: [FeeRateSource] = [
            BlockstreamFeeSource(
                baseURL: URL(string: Constants.feeRateBlockstreamURL)!,
                timeout: 5
            ),
            MempoolV1FeeSource(
                baseURL: URL(string: Constants.feeRateMempoolURL)!,
                timeout: 5
            )
        ],
        cacheTTL: Duration = .seconds(60),
        fallback: UInt64 = 2
    ) {
        self.cache = FeeRateCache(sources: sources, cacheTTL: cacheTTL, fallback: fallback)
    }

    func currentRate() async -> UInt64 {
        await cache.currentRate()
    }

    func recommendedFees() async -> RecommendedFees {
        await cache.recommendedFees()
    }

    func updateRecommendedFees(_ fees: RecommendedFees) async {
        await cache.updateRecommendedFees(fees)
    }

    func invalidate() async {
        await cache.invalidate()
    }

    /// Test seam: inject a pre-built cache.
    init(cache: FeeRateCache) {
        self.cache = cache
    }
}
