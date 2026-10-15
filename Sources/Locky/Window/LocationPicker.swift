import MapKit
import PermissionFlow
import SwiftUI

/// A weather widget's Location in Customize: the place's name, which opens a search with suggestions as you type and
/// Current Location first. A place saves as "lat,lon" with its name in place_name; Current Location saves as "".
/// While the widget follows Current Location, Location Services' row shows under it.
struct LocationOption: View {
    let location: String
    let placeName: String?
    /// Location Services' state, and its Grant.
    let permission: PermissionAuthorizationState
    let grant: () -> Void
    let commit: (_ location: String, _ name: String?) -> Void
    @State private var searching = false

    static let reason = "For the weather where this Mac is. Without it, the weather follows the time zone."

    var body: some View {
        let current = Self.isCurrent(location)
        LabeledContent("Location") {
            Button { searching = true } label: {
                Label(Self.title(location: location, placeName: placeName), systemImage: "location.fill")
                    .labelStyle(LocationLabelStyle(showsIcon: current))
                    .lineLimit(1)
            }
            .popover(isPresented: $searching, arrowEdge: .bottom) {
                LocationSearch { location, name in
                    searching = false
                    commit(location, name)
                }
            }
        }
        if current {
            PermissionRow(title: "Location Services", reason: Self.reason, state: permission, grant: grant)
        }
    }

    static func isCurrent(_ location: String) -> Bool {
        let text = location.trimmingCharacters(in: .whitespaces).lowercased()
        return text.isEmpty || text == "current"
    }

    /// What the row shows: Current Location, the place's name, its coordinates when it has no name, or a name typed in
    /// init.lua.
    static func title(location: String, placeName: String?) -> String {
        if isCurrent(location) { return "Current Location" }
        let parts = location.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2, parts.allSatisfy({ Double($0) != nil }) {
            if let placeName, !placeName.isEmpty { return placeName }
            return parts.joined(separator: ", ")
        }
        return location
    }

    /// A place's coordinates as the widget reads them: four decimals, about ten meters, with a point in any language.
    static func value(latitude: Double, longitude: Double) -> String {
        String(format: "%.4f,%.4f", latitude, longitude)
    }
}

/// The location arrow beside Current Location only.
private struct LocationLabelStyle: LabelStyle {
    let showsIcon: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            if showsIcon { configuration.icon.imageScale(.small) }
            configuration.title
        }
    }
}

/// The search: a field that suggests cities and regions as you type, under Current Location. Return picks the first
/// suggestion.
private struct LocationSearch: View {
    let pick: (_ location: String, _ name: String?) -> Void
    @State private var query = ""
    @State private var completer = PlaceCompleter()
    /// The search for a picked suggestion's coordinates, kept while it runs.
    @State private var lookup: MKLocalSearch?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search", text: $query, prompt: Text("City or region"))
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onChange(of: query) { completer.search(query) }
                .onSubmit { if let first = completer.results.first { choose(first) } }
                .padding(10)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    SuggestionRow(action: { pick("", nil) }) {
                        Label("Current Location", systemImage: "location.fill")
                    }
                    ForEach(completer.results, id: \.self) { result in
                        SuggestionRow(action: { choose(result) }) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(result.title)
                                if !result.subtitle.isEmpty { Text(result.subtitle).font(.caption).opacity(0.7) }
                            }
                        }
                    }
                }
                .padding(5)
            }
        }
        .frame(width: 280, height: 280)
        .onAppear { focused = true }
    }

    /// A suggestion's coordinates come from a search for it: the suggestion itself has only words.
    private func choose(_ result: MKLocalSearchCompletion) {
        let name = result.title
        lookup?.cancel()
        lookup = MKLocalSearch(request: MKLocalSearch.Request(completion: result))
        lookup?.start { response, _ in
            guard let coordinate = response?.mapItems.first?.placemark.coordinate else { return }
            MainActor.assumeIsolated {
                pick(LocationOption.value(latitude: coordinate.latitude, longitude: coordinate.longitude), name)
            }
        }
    }
}

/// A line of the list, highlighted under the pointer as a menu's item is.
private struct SuggestionRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .foregroundStyle(hovering ? Color.white : Color.primary)
                .background(hovering ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// MapKit's suggestions for what is typed so far: cities and regions only.
@MainActor @Observable
final class PlaceCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.addressFilter = MKAddressFilter(including: [.locality, .administrativeArea])
    }

    func search(_ text: String) {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            completer.cancel()
            results = []
        } else {
            completer.queryFragment = text
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { results = self.completer.results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        MainActor.assumeIsolated { results = [] }
    }
}
