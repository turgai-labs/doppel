actor Program {
    struct Units {
        static let celsius = "°C"
        static let scale: Double = 1.8
    }

    private static let endpoint = "https://api.open-meteo.com/v1/forecast"
    private static let variables = ["temperature_2m", "weather_code"]

    static func condition(for code: Int) -> String { code == 0 ? "clear" : "cloudy" }

    func url() -> String {
        Program.endpoint + "?current=" + Self.variables.joined(separator: ",")
    }

    func run() {
        print(url())
        print(Program.condition(for: 0), Self.condition(for: 3))
        print(Units.celsius, 20 * Units.scale + 32)
    }
}
