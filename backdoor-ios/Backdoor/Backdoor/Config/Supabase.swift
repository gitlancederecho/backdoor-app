import Foundation
import Supabase

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://qtjmwquanwovybvfvegr.supabase.co")!,
    supabaseKey: "sb_publishable_dpzRQhS9qiIC_WVwKvunig_Uhb2LPGK",
    options: SupabaseClientOptions(
        db: SupabaseClientOptions.DatabaseOptions(
            encoder: {
                let e = JSONEncoder()
                e.keyEncodingStrategy = .convertToSnakeCase
                e.dateEncodingStrategy = .iso8601
                return e
            }(),
            decoder: {
                let d = JSONDecoder()
                d.keyDecodingStrategy = .convertFromSnakeCase
                d.dateDecodingStrategy = .custom { decoder in
                    let c = try decoder.singleValueContainer()
                    let s = try c.decode(String.self)
                    let formats = [
                        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ",
                        "yyyy-MM-dd'T'HH:mm:ssZ",
                        "yyyy-MM-dd",
                    ]
                    let f = DateFormatter()
                    f.locale = Locale(identifier: "en_US_POSIX")
                    for fmt in formats {
                        f.dateFormat = fmt
                        if let date = f.date(from: s) { return date }
                    }
                    throw DecodingError.dataCorruptedError(
                        in: c,
                        debugDescription: "Cannot decode date: \(s)"
                    )
                }
                return d
            }()
        )
    )
)

let photoBucket = "task-photos"
