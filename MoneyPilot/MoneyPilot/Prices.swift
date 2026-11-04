import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Free market data: AUD/USD from Frankfurter (no key) and US share prices from Finnhub (free key).
enum Prices {
    static func audPerUSD() async throws -> Double {
        struct Rate: Decodable { var rate: Double }
        let (data, _) = try await URLSession.shared.data(from: URL(string: "https://api.frankfurter.dev/v2/rate/usd/aud")!)
        let rate = try JSONDecoder().decode(Rate.self, from: data).rate
        guard rate > 0.5, rate < 5 else { throw AppError.invalid("The exchange-rate service returned an unexpected rate.") }
        return rate
    }
    /// Latest price in US cents, or nil when Finnhub does not know the symbol (it answers 0).
    static func quote(_ symbol: String, key: String) async throws -> Money? {
        struct Quote: Decodable { var c: Double? }
        var components = URLComponents(string: "https://finnhub.io/api/v1/quote")!
        components.queryItems = [URLQueryItem(name: "symbol", value: symbol.uppercased()), URLQueryItem(name: "token", value: key)]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401, 403: throw AppError.invalid("Finnhub rejected the API key. Check it in Settings.")
        case 429: throw AppError.invalid("Finnhub's free limit was reached. Prices will refresh later.")
        case let status: throw AppError.invalid("Share prices could not be loaded (error \(status)).")
        }
        guard let price = try JSONDecoder().decode(Quote.self, from: data).c, price > 0 else { return nil }
        return centsOf(price)
    }
}
