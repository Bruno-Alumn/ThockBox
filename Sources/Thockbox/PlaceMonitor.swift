import CoreLocation

/// A place the user saved, for muting by location.
struct Place: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    let latitude: Double
    let longitude: Double
    /// Meters. Wide enough for a Mac's Wi-Fi-based location.
    var radius: Double = 200
}

/// Reports which saved places the Mac is at, using macOS's own region
/// monitoring: the system watches the places and wakes ThockBox only when
/// the Mac arrives or leaves, so it never polls or keeps location running.
/// A Mac has no low-power location hardware, so those arrivals can be late
/// or missed while it sleeps in a bag; one location fix at launch and after
/// each wake settles where it is.
/// It exists only while muting by place is on and there are places, and
/// asks for Location access only when the user adds a place.
final class PlaceMonitor: NSObject, CLLocationManagerDelegate {
    enum Access { case unknown, granted, denied }

    static var isAvailable: Bool {
        CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
    }

    private let manager = CLLocationManager()
    private var places: [Place] = []
    /// Places the Mac is inside, by ID, as far as macOS has said so far.
    private(set) var inside: Set<UUID> = []
    /// Whether macOS has reported on every place yet; until then nothing
    /// mutes, so a slow answer never silences keys by mistake.
    private var reported: Set<UUID> = []
    private let onChange: (Set<UUID>, Bool) -> Void
    private let onAccess: (Access) -> Void
    private var pendingLocation: ((CLLocation?) -> Void)?
    /// The location fix being waited for, so an old timeout can't end a newer one.
    private var locationRequest: UUID?
    /// Places whose state was asked for and not answered yet.
    private var asked: Set<UUID> = []

    init(onChange: @escaping (_ inside: Set<UUID>, _ known: Bool) -> Void, onAccess: @escaping (Access) -> Void) {
        self.onChange = onChange
        self.onAccess = onAccess
        super.init()
        manager.delegate = self
    }

    deinit {
        for region in manager.monitoredRegions { manager.stopMonitoring(for: region) }
    }

    /// Whether Location Services is on for the whole Mac.
    static var servicesEnabled: Bool { CLLocationManager.locationServicesEnabled() }

    static func access(_ status: CLAuthorizationStatus) -> Access {
        switch status {
        case .authorizedAlways, .authorized: .granted
        case .denied, .restricted: .denied
        default: .unknown
        }
    }

    var access: Access { Self.access(manager.authorizationStatus) }

    /// Watches these places (at most 20, macOS's limit for one app).
    func watch(_ places: [Place]) {
        self.places = Array(places.prefix(20))
        let ids = Set(self.places.map(\.id.uuidString))
        for region in manager.monitoredRegions where !ids.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }
        inside = inside.filter { id in self.places.contains { $0.id == id } }
        reported = reported.filter { id in self.places.contains { $0.id == id } }
        guard access == .granted else { report(); return }
        // macOS keeps watching an app's regions across launches, so a place
        // can be watched already and still have no state in this run: ask
        // for every place without an answer (once), not only new ones.
        // Renaming a place changes nothing here.
        let watched = Set(manager.monitoredRegions.map(\.identifier))
        var askedSome = false
        for place in self.places where !reported.contains(place.id) && !asked.contains(place.id) {
            let region = Self.region(for: place)
            if !watched.contains(place.id.uuidString) { manager.startMonitoring(for: region) }
            asked.insert(place.id)
            manager.requestState(for: region)
            askedSome = true
        }
        if askedSome { refresh() }
        report()
    }

    /// Checks where the Mac is with one location fix: at launch, when a
    /// place is added, and after the Mac wakes, when region monitoring alone
    /// may not have noticed a move.
    func refresh() {
        guard access == .granted, !places.isEmpty, pendingLocation == nil else { return }
        manager.requestLocation()
    }

    /// The fixes worth trusting: recent, and no vaguer than a few blocks.
    static func isUsable(_ location: CLLocation, now: Date = Date()) -> Bool {
        location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 500
            && now.timeIntervalSince(location.timestamp) < 120
    }

    /// The places a fix is inside, by distance from each place's center.
    static func places(_ places: [Place], containing location: CLLocation) -> Set<UUID> {
        Set(places.filter {
            location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= $0.radius
        }.map(\.id))
    }

    static func region(for place: Place) -> CLCircularRegion {
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
            radius: place.radius, identifier: place.id.uuidString)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        return region
    }

    /// Asks for Location access if the user hasn't answered yet: as soon as
    /// muting by place is turned on, so the prompt comes when it makes sense.
    func requestAccess() {
        guard access == .unknown, CLLocationManager.locationServicesEnabled() else { return }
        manager.requestAlwaysAuthorization()
    }

    /// One location fix, for adding the current place. Asks for access first
    /// if needed; nil if it's refused or the Mac can't tell where it is.
    func currentLocation(_ done: @escaping (CLLocation?) -> Void) {
        guard CLLocationManager.locationServicesEnabled() else { return done(nil) }
        pendingLocation = done
        let request = UUID()
        locationRequest = request
        // Without an answer (no prompt shown, no fix), give up rather than
        // leave the spinner going.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            if self?.locationRequest == request { self?.finishLocation(nil) }
        }
        switch access {
        // Keeps trying until a fix arrives or the timeout: a single request
        // often fails at first on a Mac, while Wi-Fi is still being scanned.
        case .granted: manager.startUpdatingLocation()
        case .denied: finishLocation(nil)
        case .unknown: manager.requestAlwaysAuthorization()
        }
    }

    private func finishLocation(_ location: CLLocation?) {
        guard pendingLocation != nil else { return }
        manager.stopUpdatingLocation()
        let done = pendingLocation
        pendingLocation = nil
        locationRequest = nil
        klog.notice("location fix: \(location.map { "within \(Int($0.horizontalAccuracy)) m" } ?? "none", privacy: .public)")
        done?(location)
    }

    /// `known` is whether every place has an answer; the places reported
    /// inside count either way.
    private func report() {
        guard access == .granted else { return onChange([], false) }
        let known = places.allSatisfy { reported.contains($0.id) }
        onChange(inside, known)
    }

    private func set(_ state: CLRegionState, for region: CLRegion) {
        guard let id = UUID(uuidString: region.identifier), places.contains(where: { $0.id == id }) else { return }
        reported.insert(id)
        asked.remove(id)
        switch state {
        case .inside: inside.insert(id)
        case .outside: inside.remove(id)
        case .unknown: reported.remove(id)
        @unknown default: break
        }
        report()
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        klog.notice("location access: \(String(describing: self.access), privacy: .public)")
        onAccess(access)
        // Granted again after a refusal: every place needs asking again.
        asked = []
        if access != .granted { reported = []; inside = [] }
        if pendingLocation != nil {
            switch access {
            case .granted: manager.startUpdatingLocation()
            case .denied: finishLocation(nil)
            case .unknown: break
            }
        }
        watch(places)
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        set(state, for: region)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        set(.inside, for: region)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        set(.outside, for: region)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, Self.isUsable(location) else { return }
        // A fix says where the Mac is for every place at once.
        inside = Self.places(places, containing: location)
        reported = Set(places.map(\.id))
        asked = []
        if pendingLocation != nil { finishLocation(location) }
        report()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        klog.notice("location failed: \(error.localizedDescription, privacy: .public)")
        // "Unknown" means not yet: keep waiting for the fix or the timeout.
        if (error as? CLError)?.code == .locationUnknown { return }
        finishLocation(nil)
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        guard let region, let id = UUID(uuidString: region.identifier) else { return }
        klog.notice("watching a place failed: \(error.localizedDescription, privacy: .public)")
        set(.unknown, for: region)
        // Try again a minute later rather than leave the place unknown.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self, let place = self.places.first(where: { $0.id == id }) else { return }
            self.asked.remove(id)
            self.manager.stopMonitoring(for: region)
            self.manager.startMonitoring(for: Self.region(for: place))
            self.watch(self.places)
        }
    }
}
