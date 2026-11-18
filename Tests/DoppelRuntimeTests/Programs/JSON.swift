import Foundation

struct Forecast: Codable {
    struct Daily: Codable {
        var time: [String]
        var highs: [Double]
    }

    var latitude: Double
    var timezone: String?
    var daily: Daily
}

struct Note: Decodable {
    var text: String
    var tags: [String: Int]
}

enum Mood: String, Codable {
    case calm
    case busy
}

struct Day: Codable {
    var mood: Mood
    var steps: Int
    var done: Bool
}

actor Program {
    func run() {
        let body = """
            {"latitude": 52.52, "longitude": 13.41,
             "daily": {"time": ["2026-11-18", "2026-11-19"], "highs": [11.5, 9]}}
            """
        do {
            let forecast = try JSONDecoder().decode(Forecast.self, from: body.data(using: .utf8)!)
            print(forecast.latitude, forecast.timezone ?? "none")
            print(forecast.daily.time, forecast.daily.highs)
        } catch {
            print("failed")
        }

        let note = try? JSONDecoder().decode(Note.self, from: Data(#"{"text": "hi", "tags": {"a": 1}}"#.utf8))
        print(note?.text ?? "none", note?.tags["a"] ?? 0)

        let north = #"{"latitude": "north", "daily": {"time": [], "highs": []}}"#
        let wrongType = try? JSONDecoder().decode(Forecast.self, from: Data(north.utf8))
        print(wrongType == nil)
        let missing = try? JSONDecoder().decode(Forecast.self, from: Data(#"{"latitude": 1}"#.utf8))
        print(missing == nil)
        let notJSON = try? JSONDecoder().decode(Note.self, from: Data("not json".utf8))
        print(notJSON == nil)

        let days = [Day(mood: .calm, steps: 4200, done: true), Day(mood: .busy, steps: 12000, done: false)]
        do {
            let written = try JSONEncoder().encode(days)
            let read = try JSONDecoder().decode([Day].self, from: written)
            print(read.count, read[0].mood, read[1].steps, read[1].done)
        } catch {
            print("failed")
        }
    }
}
