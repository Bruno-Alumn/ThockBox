import Foundation

/// A new GitHub issue with the versions filled in, so a report says what it
/// ran on without anyone asking. Nothing else about the Mac is included.
enum ProblemReport {
    static func url(appVersion: String = AppVersion.current,
                    osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString) -> URL {
        let body = """
        What happened?



        What did you expect?



        ThockBox \(appVersion), macOS \(osVersion)
        """
        var components = URLComponents(string: "https://github.com/Bruno-Alumn/ThockBox/issues/new")!
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        return components.url!
    }
}
