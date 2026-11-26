import Foundation

struct Weather: Codable {
    let temperature: Double
    let windSpeed: Double
    var note: String = "from the web"

    enum CodingKeys: String, CodingKey {
        case temperature = "temperature_2m"
        case windSpeed = "wind_speed_10m"
    }
}

struct Forecast: Codable {
    let latitude: Double
    let current: Weather
    let hourly: [Weather]?
}

struct Tally: Codable {
    let name: String
    let count: Int
    var seen = 0

    enum CodingKeys: CodingKey {
        case name, count
    }
}

enum Unit: String, Codable {
    case celsius, fahrenheit
}

struct Setting: Codable {
    let unit: Unit
    let place: String

    enum CodingKeys: String, CodingKey {
        case unit
        case place = "location"
    }
}

enum Numbered: Int, CodingKey {
    case first = 1
    case second
}

actor Program {
    func run() {
        let json =
            "{\"latitude\": 48.1, \"current\": {\"temperature_2m\": 7.5, \"wind_speed_10m\": 12.0}, \"hourly\": [{\"temperature_2m\": 6.0, \"wind_speed_10m\": 3.5, \"note\": \"ignored\"}]}"
        do {
            let forecast = try JSONDecoder().decode(Forecast.self, from: Data(json.utf8))
            print(forecast.latitude, forecast.current.temperature, forecast.current.windSpeed, forecast.current.note)
            print(
                forecast.hourly?.count ?? 0, forecast.hourly?.first?.temperature ?? 0,
                forecast.hourly?.first?.note ?? "")
            // What each holds, by its keys: Foundation's order of keys isn't fixed.
            let current = try JSONEncoder().encode(forecast.current)
            let written = String(decoding: current, as: UTF8.self)
            print(
                written.contains("\"temperature_2m\":7.5"), written.contains("\"wind_speed_10m\":12"),
                written.contains("note"))
            let back = try JSONDecoder().decode(Weather.self, from: current)
            print(back.temperature, back.windSpeed, back.note)
        } catch {
            print("not read")
        }

        do {
            var tally = try JSONDecoder().decode(
                Tally.self, from: Data("{\"name\": \"cups\", \"count\": 3, \"seen\": 9}".utf8))
            print(tally.name, tally.count, tally.seen)
            tally.seen = 5
            let written = String(decoding: try JSONEncoder().encode(tally), as: UTF8.self)
            print(written.contains("\"name\":\"cups\""), written.contains("\"count\":3"), written.contains("seen"))
        } catch {
            print("not read")
        }

        do {
            let setting = try JSONDecoder().decode(
                Setting.self, from: Data("{\"unit\": \"celsius\", \"location\": \"Munich\"}".utf8))
            print(setting.unit, setting.place)
            let written = String(decoding: try JSONEncoder().encode(setting), as: UTF8.self)
            print(
                written.contains("\"location\":\"Munich\""), written.contains("\"unit\":\"celsius\""),
                written.contains("place"))
        } catch {
            print("not read")
        }
        do {
            _ = try JSONDecoder().decode(
                Setting.self, from: Data("{\"unit\": \"celsius\", \"place\": \"Munich\"}".utf8))
            print("read")
        } catch {
            print("not read: no location")
        }

        // The keys themselves, as Swift says them.
        print(Weather.CodingKeys.temperature.stringValue, Weather.CodingKeys.temperature.intValue == nil)
        print(Tally.CodingKeys.count.stringValue, Tally.CodingKeys.count.intValue == nil)
        print(Numbered.second.stringValue, Numbered.second.intValue ?? 0)
        print(Setting.CodingKeys.place)
        print([Numbered.first, Numbered.second])
        print("\(Weather.CodingKeys.windSpeed)")
    }
}
