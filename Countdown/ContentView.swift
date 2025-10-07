//
//  Countdown.swift
//  Countdown
//
//  Minimalistische SwiftUI App mit Events (Bild lokal/Unsplash), Farbe, Countdown und Persistenz.
//  iOS 15+ empfohlen.
//

import SwiftUI
import Combine
import PhotosUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// --------------------------
// MARK: - CONFIG
// --------------------------

// Trage hier deinen Unsplash Access Key ein oder setze leer, wenn du keine Unsplash-Funktionalität willst.
// Erstellen: https://unsplash.com/developers
fileprivate let UNSPLASH_ACCESS_KEY = "UrLvQgQcrwxO53CCg5WKp65nEw2Q71KGyrorbaAfu-8"

// --------------------------
// MARK: - Models
// --------------------------

struct Event: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var date: Date
    var bgHex: String            // Hintergrundfarbe als Hex (z. B. "#FFA500")
    var imageFilename: String?   // falls lokal gespeichert (JPG)
    var remoteImageURL: String?  // falls geladen von Unsplash (Original URL cached)
    var createdAt: Date
    
    init(id: UUID = UUID(), title: String, date: Date, bgHex: String, imageFilename: String? = nil, remoteImageURL: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.date = date
        self.bgHex = bgHex
        self.imageFilename = imageFilename
        self.remoteImageURL = remoteImageURL
        self.createdAt = createdAt
    }
}

// --------------------------
// MARK: - Persistence
// --------------------------

class EventStore: ObservableObject {
    @Published var events: [Event] = []
    
    private let filename = "events.json"
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        load()
        // Save automatically when events change
        $events
            .sink { [weak self] _ in
                self?.save()
            }
            .store(in: &cancellables)
    }
    
    private func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private func eventsFileURL() -> URL {
        documentsURL().appendingPathComponent(filename)
    }
    
    func save() {
        do {
            let data = try JSONEncoder().encode(events)
            try data.write(to: eventsFileURL(), options: [.atomicWrite])
        } catch {
            print("Fehler beim Speichern der Events: \(error)")
        }
    }
    
    func load() {
        do {
            let url = eventsFileURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                self.events = []
                return
            }
            let data = try Data(contentsOf: url)
            self.events = try JSONDecoder().decode([Event].self, from: data)
        } catch {
            print("Fehler beim Laden der Events: \(error)")
            self.events = []
        }
    }
    
    func add(_ event: Event) {
        events.insert(event, at: 0)
        save() // explizit speichern
    }
    
    func remove(at offsets: IndexSet) {
        for index in offsets {
            let e = events[index]
            if let filename = e.imageFilename {
                try? FileManager.default.removeItem(at: documentsURL().appendingPathComponent(filename))
            }
        }
        events.remove(atOffsets: offsets)
        save() // explizit speichern
    }
    
    func move(from source: IndexSet, to destination: Int) {
        events.move(fromOffsets: source, toOffset: destination)
        save() // nach Reorder speichern
    }
}

// --------------------------
// MARK: - Utilities
// --------------------------

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    // Return luminance (0...1)
    func luminance() -> Double {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        func comp(_ c: CGFloat) -> Double {
            let c = Double(c)
            return c <= 0.03928 ? c/12.92 : pow((c+0.055)/1.055, 2.4)
        }
        let L = 0.2126 * comp(r) + 0.7152 * comp(g) + 0.0722 * comp(b)
        return L
    }
}

extension Color {
    func toHexString() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(r * 255)
        let gi = Int(g * 255)
        let bi = Int(b * 255)
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}

// Format remaining time (compact: days, hours, minutes)
func formatRemaining(until target: Date) -> String {
    let now = Date()
    if target <= now {
        return "Jetzt!"
    }
    let cal = Calendar.current
    let comps = cal.dateComponents([.day, .hour, .minute, .second], from: now, to: target)
    let d = comps.day ?? 0
    let h = comps.hour ?? 0
    let m = comps.minute ?? 0
    return "\(d) Tage, \(h) Stunden, \(m) Minuten"
}

// Full remaining time incl. seconds
func formatRemainingFull(until target: Date) -> String {
    let now = Date()
    if target <= now {
        return "Jetzt!"
    }
    let cal = Calendar.current
    let comps = cal.dateComponents([.day, .hour, .minute, .second], from: now, to: target)
    let d = comps.day ?? 0
    let h = comps.hour ?? 0
    let m = comps.minute ?? 0
    let s = comps.second ?? 0
    return "\(d) Tage, \(h) Stunden, \(m) Minuten und \(s) Sekunden"
}

// Save UIImage to Documents and return filename
func saveImageToDocuments(_ image: UIImage) throws -> String {
    guard let data = image.jpegData(compressionQuality: 0.85) else {
        throw NSError(domain: "SaveError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not convert to JPEG"])
    }
    let filename = "img_\(UUID().uuidString).jpg"
    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
    try data.write(to: url, options: .atomic)
    return filename
}

func loadImageFromDocuments(filename: String) -> UIImage? {
    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
    return UIImage(contentsOfFile: url.path)
}

// Async Unsplash image search (returns direct image URL string or nil)
enum UnsplashError: Error {
    case noKey
    case noResults
    case network(Error)
    case badResponse
}

func fetchUnsplashImageURL(query: String) async throws -> String {
    guard !UNSPLASH_ACCESS_KEY.isEmpty else { throw UnsplashError.noKey }
    let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
    let urlString = "https://api.unsplash.com/search/photos?query=\(q)&per_page=10"
    guard let url = URL(string: urlString) else { throw UnsplashError.badResponse }
    var req = URLRequest(url: url)
    req.setValue("Client-ID \(UNSPLASH_ACCESS_KEY)", forHTTPHeaderField: "Authorization")
    let (data, resp): (Data, URLResponse)
    do {
        (data, resp) = try await URLSession.shared.data(for: req)
    } catch {
        throw UnsplashError.network(error)
    }
    guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
        throw UnsplashError.badResponse
    }
    // Parse JSON (simple)
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let results = json["results"] as? [[String: Any]],
       let first = results.first,
       let urls = first["urls"] as? [String: Any],
       let thumb = urls["regular"] as? String {
        return thumb
    } else {
        throw UnsplashError.noResults
    }
}

// Download image data from URL
func downloadImage(from urlString: String) async throws -> UIImage {
    guard let url = URL(string: urlString) else { throw UnsplashError.badResponse }
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200, let img = UIImage(data: data) else {
        throw UnsplashError.badResponse
    }
    return img
}

// Average color from image using Core Image
func averageColor(from image: UIImage) -> Color? {
    guard let ciImage = CIImage(image: image) else { return nil }
    let filter = CIFilter.areaAverage()
    filter.inputImage = ciImage
    filter.extent = ciImage.extent
    
    let context = CIContext(options: [.workingColorSpace: NSNull()])
    var bitmap = [UInt8](repeating: 0, count: 4)
    guard let output = filter.outputImage else { return nil }
    let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
    context.render(output, toBitmap: &bitmap, rowBytes: 4, bounds: rect, format: .RGBA8, colorSpace: nil)
    
    let r = Double(bitmap[0]) / 255.0
    let g = Double(bitmap[1]) / 255.0
    let b = Double(bitmap[2]) / 255.0
    let a = Double(bitmap[3]) / 255.0
    return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
}

// --------------------------
// MARK: - ImagePicker (PHPicker)
// --------------------------

struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { image, _ in
                DispatchQueue.main.async {
                    if let ui = image as? UIImage { self.parent.image = ui }
                }
            }
        }
    }
}

// --------------------------
// MARK: - Views
// --------------------------

struct EventListView: View {
    @EnvironmentObject var store: EventStore
    @State private var showingAddFlow = false
    @State private var expandedIDs: Set<UUID> = []
    @State private var editMode: EditMode = .inactive
    
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 8) {
                // Header: Titel + Plus auf einer Höhe (Sortieren-Button entfernt)
                HStack(spacing: 10) {
                    Text("Countdown")
                        .font(.largeTitle).bold()
                    Spacer()
                    // Add new
                    Button {
                        showingAddFlow = true
                    } label: {
                        Image(systemName: "plus")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.primary)
                            .font(.system(size: 16, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(
                                Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Neues Ereignis")
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                
                if store.events.isEmpty {
                    // Empty State – leicht grauer Text, zentriert
                    VStack(spacing: 12) {
                        Text("Klick auf das Plus um dein erstes Ereignis hinzu zu fügen")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .transition(.opacity)
                } else {
                    List {
                        // Events
                        ForEach(store.events) { event in
                            EventCardView(
                                event: event,
                                isExpanded: expandedIDs.contains(event.id),
                                onToggle: { toggleExpanded(event.id) }
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                        }
                        .onMove(perform: store.move)
                        .onDelete(perform: store.remove)
                        
                        // Footer: Sortieren/Fertig Button – zentriert unter dem letzten Ereignis
                        HStack {
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    editMode = (editMode == .active) ? .inactive : .active
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.up.arrow.down")
                                    Text(editMode == .active ? "Fertig" : "Sortieren")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(
                                    Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 24, trailing: 16))
                    }
                    .listStyle(.plain)
                    .environment(\.editMode, $editMode)
                }
            }
            .fullScreenCover(isPresented: $showingAddFlow) {
                AddEventWizardView(isPresented: $showingAddFlow)
                    .environmentObject(store)
            }
        }
    }
    
    private func toggleExpanded(_ id: UUID) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            if expandedIDs.contains(id) { expandedIDs.remove(id) }
            else { expandedIDs.insert(id) }
        }
    }
}

struct EventCardView: View {
    let event: Event
    let isExpanded: Bool
    let onToggle: () -> Void
    
    @State private var localImage: UIImage? = nil
    @State private var remoteImage: Image? = nil
    @State private var isLoadingRemote = false
    
    // Timer to refresh countdown every second
    @State private var now = Date()
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    // Einheitliche Höhen: collapsedHeight für alle Karten, expandedHeight für aufgeklappte
    private let collapsedHeight: CGFloat = 150
    private let expandedHeight: CGFloat = 220
    
    var body: some View {
        let bgColor = Color(hex: event.bgHex)
        let textColor = bgColor.luminance() < 0.5 ? Color.white : Color.black
        
        ZStack(alignment: .leading) {
            // Hintergrundkarte
            RoundedRectangle(cornerRadius: 20)
                .fill(bgColor)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: isExpanded ? 10 : 8) {
                    Text(formattedDate(event.date))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(textColor.opacity(0.9))
                    
                    Text(event.title)
                        .font(.system(size: isExpanded ? 28 : 26, weight: .bold))
                        .foregroundColor(textColor)
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .minimumScaleFactor(0.45)
                        .allowsTightening(true)
                    
                    Text(isExpanded ? formatRemainingFull(until: event.date) : formatRemaining(until: event.date))
                        .font(isExpanded ? .headline.weight(.semibold) : .headline)
                        .foregroundColor(textColor.opacity(0.95))
                }
                
                Spacer(minLength: 10)
                
                ZStack {
                    Circle().frame(width: 110, height: 110).foregroundColor(.clear)
                    if let ui = localImage {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 110, height: 110)
                            .clipShape(Circle())
                    } else if let r = remoteImage {
                        r
                            .resizable()
                            .scaledToFill()
                            .frame(width: 110, height: 110)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 110, height: 110)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.title2)
                                    .foregroundColor(textColor.opacity(0.7))
                            )
                    }
                }
            }
            .padding(20)
        }
        .frame(height: isExpanded ? expandedHeight : collapsedHeight)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: isExpanded)
        .onAppear {
            if let filename = event.imageFilename {
                self.localImage = loadImageFromDocuments(filename: filename)
            } else if let urlStr = event.remoteImageURL {
                Task { await fetchRemote(urlStr: urlStr) }
            }
        }
        .onReceive(timer) { input in
            self.now = input
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        return f.string(from: date)
    }
    
    private func fetchRemote(urlStr: String) async {
        guard !isLoadingRemote else { return }
        isLoadingRemote = true
        defer { isLoadingRemote = false }
        do {
            let img = try await downloadImage(from: urlStr)
            await MainActor.run {
                self.remoteImage = Image(uiImage: img)
            }
        } catch {
            print("Remote image fetch failed: \(error)")
        }
    }
}

// --------------------------
// MARK: - AddEventWizard (Fenster-zu-Fenster-Flow, Toolbar-Icons „Liquid Glass“)
// --------------------------

struct AddEventWizardView: View {
    enum Step: Int { case title, dateTime, image, color, review }
    
    @EnvironmentObject var store: EventStore
    @Binding var isPresented: Bool
    
    @State private var step: Step = .title
    
    // Shared State
    @State private var title: String = ""
    @State private var date: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var useTime: Bool = false // Standardmäßig aus
    @State private var pickedImage: UIImage? = nil
    @State private var bgColor: Color = Color(.secondarySystemBackground)
    
    // Unsplash + Picker
    @State private var isLoadingUnsplash = false
    @State private var unsplashError: String? = nil
    @State private var showPhotoPicker = false
    
    // Layout helpers
    private var normalizedDate: Date {
        useTime ? date : Calendar.current.startOfDay(for: date)
    }
    private var canProceed: Bool {
        switch step {
        case .title: return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .dateTime, .image, .color: return true
        case .review: return false
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Live-Vorschau oben – baut sich Schritt für Schritt auf
                    PreviewEventCard(
                        title: title,
                        date: normalizedDate,
                        image: pickedImage,
                        color: step.rawValue >= Step.color.rawValue ? bgColor : Color(.secondarySystemBackground)
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    
                    Divider().padding(.top, 12)
                    
                    // Schrittinhalt
                    Group {
                        switch step {
                        case .title:
                            StepTitleView(title: $title)
                        case .dateTime:
                            StepDateTimeView(date: $date, useTime: $useTime)
                        case .image:
                            StepImageView(
                                title: title,
                                pickedImage: $pickedImage,
                                isLoadingUnsplash: $isLoadingUnsplash,
                                unsplashError: $unsplashError,
                                onPick: { showPhotoPicker = true },
                                onUnsplash: { Task { await fetchUnsplash() } },
                                onAfterPick: suggestColorFromImage
                            )
                        case .color:
                            StepColorView(
                                pickedImage: pickedImage,
                                color: $bgColor,
                                onSuggestColor: suggestColorFromImage
                            )
                        case .review:
                            StepReviewView(
                                title: title,
                                date: normalizedDate,
                                useTime: useTime,
                                color: bgColor
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Leading: Abbrechen (x) oder Zurück (chevron.left) – Liquid Glass
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if step == .title { isPresented = false }
                        else { goPrevious() }
                    } label: {
                        Image(systemName: step == .title ? "xmark" : "chevron.left")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.primary)
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
                // Title
                ToolbarItem(placement: .principal) {
                    Text(titleFor(step)).font(.headline)
                }
                // Trailing: Weiter (chevron.right) oder Speichern (checkmark) – Liquid Glass
                ToolbarItem(placement: .navigationBarTrailing) {
                    if step == .review {
                        Button {
                            saveEvent()
                        } label: {
                            Image(systemName: "checkmark")
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(.primary)
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Button {
                            goNext()
                        } label: {
                            Image(systemName: "chevron.right")
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(.primary)
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canProceed)
                    }
                }
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker(image: Binding(get: { pickedImage }, set: { new in
                pickedImage = new
                suggestColorFromImage()
            }))
        }
    }
    
    private func titleFor(_ step: Step) -> String {
        switch step {
        case .title: return "Titel"
        case .dateTime: return "Datum & Uhrzeit"
        case .image: return "Bild"
        case .color: return "Farbe"
        case .review: return "Übersicht"
        }
    }
    private func goNext() {
        if let next = Step(rawValue: step.rawValue + 1) {
            withAnimation(.easeInOut) { step = next }
        }
    }
    private func goPrevious() {
        if let prev = Step(rawValue: step.rawValue - 1) {
            withAnimation(.easeInOut) { step = prev }
        }
    }
    private func suggestColorFromImage() {
        if let img = pickedImage, let avg = averageColor(from: img) {
            bgColor = avg
        }
    }
    private func saveEvent() {
        var filename: String? = nil
        if let img = pickedImage {
            do { filename = try saveImageToDocuments(img) }
            catch { print("Konnte Bild nicht speichern: \(error)") }
        }
        let e = Event(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            date: normalizedDate,
            bgHex: bgColor.toHexString(),
            imageFilename: filename,
            remoteImageURL: nil
        )
        store.add(e)
        isPresented = false
    }
    private func fetchUnsplash() async {
        guard !UNSPLASH_ACCESS_KEY.isEmpty else {
            unsplashError = "Unsplash Access Key fehlt."
            return
        }
        isLoadingUnsplash = true
        unsplashError = nil
        do {
            let query = title.isEmpty ? "nature" : title
            let urlString = try await fetchUnsplashImageURL(query: query)
            let ui = try await downloadImage(from: urlString)
            await MainActor.run {
                self.pickedImage = ui
                self.suggestColorFromImage()
                self.isLoadingUnsplash = false
            }
        } catch UnsplashError.noResults {
            unsplashError = "Keine passenden Bilder gefunden."
            isLoadingUnsplash = false
        } catch {
            unsplashError = "Fehler: \(error.localizedDescription)"
            isLoadingUnsplash = false
        }
    }
}

// --------------------------
// MARK: - Vorschau-Karte (live, oben)
// --------------------------

private struct PreviewEventCard: View {
    let title: String
    let date: Date
    let image: UIImage?
    let color: Color
    
    var body: some View {
        let textColor = color.luminance() < 0.5 ? Color.white : Color.black
        VStack(alignment: .leading, spacing: 10) {
            Text("Vorschau")
                .font(.caption)
                .foregroundColor(.secondary)
            
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(color)
                    .frame(height: 150)
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(shortDate(date))
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(textColor.opacity(0.9))
                        Text(title.isEmpty ? "Ereignis" : title)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(textColor)
                            .lineLimit(2)
                            .minimumScaleFactor(0.45)
                            .allowsTightening(true)
                        Text(formatRemaining(until: date))
                            .font(.headline)
                            .foregroundColor(textColor.opacity(0.95))
                    }
                    Spacer(minLength: 10)
                    ZStack {
                        Circle().frame(width: 110, height: 110).foregroundColor(.clear)
                        if let ui = image {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 110, height: 110)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.white.opacity(0.25))
                                .frame(width: 110, height: 110)
                                .overlay(
                                    Image(systemName: "photo")
                                        .font(.title2)
                                        .foregroundColor(textColor.opacity(0.7))
                                )
                        }
                    }
                }
                .padding(20)
            }
        }
    }
    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        return f.string(from: d)
    }
}

// --------------------------
// MARK: - Wizard-Schritte
// --------------------------

private struct StepTitleView: View {
    @Binding var title: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Wie heißt dein Ereignis?")
                .font(.title2).bold()
            TextField("Titel eingeben", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
            Spacer()
        }
        .padding(24)
    }
}

private struct StepDateTimeView: View {
    @Binding var date: Date
    @Binding var useTime: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Wann findet es statt?")
                .font(.title2).bold()
            
            DatePicker("Datum", selection: $date, displayedComponents: [.date])
                .datePickerStyle(.graphical)
            
            Toggle(isOn: $useTime.animation()) {
                Label("Uhrzeit verwenden", systemImage: "clock")
            }
            .onChange(of: useTime) { newValue in
                if !newValue { date = Calendar.current.startOfDay(for: date) }
            }
            
            if useTime {
                DatePicker("Uhrzeit", selection: $date, displayedComponents: [.hourAndMinute])
                    .datePickerStyle(.wheel)
            }
            Spacer()
        }
        .padding(24)
    }
}

private struct StepImageView: View {
    let title: String
    @Binding var pickedImage: UIImage?
    @Binding var isLoadingUnsplash: Bool
    @Binding var unsplashError: String?
    
    var onPick: () -> Void
    var onUnsplash: () -> Void
    var onAfterPick: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Bild hinzufügen (optional)")
                .font(.title2).bold()
            
            if let ui = pickedImage {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .cornerRadius(16)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 220)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(.secondary)
                                .font(.system(size: 44, weight: .medium))
                            Text("Füge ein Bild hinzu (optional)")
                                .foregroundColor(.secondary)
                        }
                    )
            }
            
            HStack(spacing: 12) {
                Button(action: { onPick() }) {
                    Image(systemName: "photo.on.rectangle")
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.primary)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                
                Button(action: { onUnsplash() }) {
                    Image(systemName: "sparkles")
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.primary)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isLoadingUnsplash)
            }
            
            if isLoadingUnsplash {
                ProgressView("Lade Vorschlag …")
            }
            if let err = unsplashError {
                Text(err).foregroundColor(.red).font(.caption)
            }
            Spacer()
        }
        .padding(24)
        .onChange(of: pickedImage) { _ in onAfterPick() }
    }
}

private struct StepColorView: View {
    let pickedImage: UIImage?
    @Binding var color: Color
    var onSuggestColor: () -> Void
    
    private let presets: [Color] = [
        Color(hex: "#F4A261"), Color(hex: "#E76F51"), Color(hex: "#2A9D8F"),
        Color(hex: "#264653"), Color(hex: "#E9C46A"), Color(hex: "#8AB17D"),
        Color(hex: "#6B5B95"), Color(hex: "#FF6F61")
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Farbe wählen")
                    .font(.title2).bold()
                
                RoundedRectangle(cornerRadius: 12)
                    .fill(color)
                    .frame(height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                
                HStack(spacing: 12) {
                    ColorPicker("Farbe", selection: $color)
                        .labelsHidden()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(presets, id: \.self) { c in
                                Button { color = c } label: {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(c)
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                        )
                                }
                            }
                        }
                    }
                    
                    Button {
                        onSuggestColor()
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.primary)
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Farbe aus Bild vorschlagen")
                    .disabled(pickedImage == nil)
                }
                Spacer()
            }
            .padding(24)
        }
    }
}

// MARK: - Schritt 5: Übersicht (ohne Vorschau)

private struct StepReviewView: View {
    let title: String
    let date: Date
    let useTime: Bool
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Alles bereit?")
                .font(.title2).bold()
            
            VStack(alignment: .leading, spacing: 8) {
                Label("Titel: \(title.isEmpty ? "—" : title)", systemImage: "textformat")
                if useTime {
                    Label("Datum: \(formattedDateLong(date))", systemImage: "calendar")
                } else {
                    Label("Datum: \(formattedDateOnly(date)) (00:00 Uhr)", systemImage: "calendar")
                }
                Label("Farbe: \(color.toHexString())", systemImage: "paintpalette")
            }
            .font(.body)
            Spacer()
        }
        .padding(24)
    }
    
    private func formattedDateLong(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
    private func formattedDateOnly(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}
