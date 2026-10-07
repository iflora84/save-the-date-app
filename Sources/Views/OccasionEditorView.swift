import SwiftUI
import UIKit
import PhotosUI

struct OccasionEditorView: View {
    let isNew: Bool
    let onSave: (Occasion) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: OccasionStore

    @State private var draft: Occasion
    @State private var includeYear: Bool
    @State private var repeatsYearly: Bool
    @State private var year: Int
    @State private var reminderTime: Date
    @State private var customDays: Int = 10
    @State private var emojiText: String = ""
    @State private var photoItem: PhotosPickerItem? = nil
    /// Framed in the cropper but not yet written; both reach disk only on Save.
    @State private var pendingPhoto: UIImage? = nil
    /// A newly picked whole photo. Nil keeps the one already saved.
    @State private var pendingFull: UIImage? = nil
    @State private var cropRequest: CropRequest? = nil
    @FocusState private var customFocused: Bool

    /// `prefill` starts a new date from something found in text or a screenshot.
    init(editing occasion: Occasion?, defaultReminderHour: Int, defaultReminderMinute: Int, prefill: Occasion? = nil, onSave: @escaping (Occasion) -> Void) {
        let currentYear: Int = OccasionEditorView.currentYear()
        self.isNew = occasion == nil
        self.onSave = onSave

        let initialDraft: Occasion
        if let existing = occasion {
            initialDraft = existing
        } else if let found = prefill {
            initialDraft = found
        } else {
            let now = Date()
            let month = Calendar.current.component(.month, from: now)
            let day = Calendar.current.component(.day, from: now)
            initialDraft = Occasion(
                name: "",
                kind: .birthday,
                emoji: nil,
                month: month,
                day: day,
                year: nil,
                reminderOffsets: Occasion.defaultReminderOffsets,
                reminderHour: defaultReminderHour,
                reminderMinute: defaultReminderMinute,
                note: "",
                palette: OccasionPalette.random()
            )
        }

        let hour = initialDraft.reminderHour
        let minute = initialDraft.reminderMinute

        _draft = State(initialValue: initialDraft)
        let start = occasion ?? prefill
        _includeYear = State(initialValue: start?.year != nil)
        _repeatsYearly = State(initialValue: !(start?.isOneTime ?? false))
        _year = State(initialValue: start?.year ?? (currentYear - 30))
        _reminderTime = State(initialValue: Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date())
    }

    private static func currentYear() -> Int {
        return Calendar.current.component(.year, from: Date())
    }

    /// A yearly date started in the past; a one-time date such as a trip can be years ahead.
    private var years: [Int] {
        let current = OccasionEditorView.currentYear()
        let latest = repeatsYearly ? current : current + 10
        return Array((1900...latest).reversed())
    }

    private var canSave: Bool {
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && OccasionMath.isValid(month: draft.month, day: draft.day)
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                kindSection
                photoSection
                emojiSection
                colorSection
                whenSection
                remindSection
                noteSection
            }
            .scrollDismissesKeyboard(.interactively)
            .themedFormBackground()
            .onChange(of: photoItem) { _, item in
                Task { await loadPhoto(item) }
            }
            .fullScreenCover(item: $cropRequest) { request in
                PhotoCropView(image: request.image) { cropped in
                    pendingPhoto = cropped
                    if request.isNewPhoto {
                        pendingFull = request.image
                    }
                }
            }
            .navigationTitle(isNew ? "New date" : "Edit date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { customFocused = false }
                }
            }
        }
    }

    private var nameSection: some View {
        Section("Who or what") {
            TextField("Mom, Alex & Sam, Trip to Japan…", text: $draft.name)
        }
    }

    private var kindSection: some View {
        Section("Kind") {
            HStack(spacing: 8) {
                ForEach(OccasionKind.allCases) { kind in
                    Chip(kind.label, isSelected: draft.kind == kind) {
                        selectKind(kind)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var hasPhoto: Bool {
        return pendingPhoto != nil || draft.photoFileName != nil
    }

    private var photoSection: some View {
        Section {
            HStack(spacing: 16) {
                photoPreview
                VStack(alignment: .leading, spacing: 10) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Text(hasPhoto ? "Change photo" : "Add a photo")
                    }
                    .buttonStyle(.borderless)
                    if hasPhoto {
                        Button("Adjust") { adjustPhoto() }
                            .buttonStyle(.borderless)
                        Button("Remove photo", role: .destructive) { removePhoto() }
                            .buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            Text("Photo")
        } footer: {
            Text("Shown on the card instead of the emoji. It stays on this iPhone.")
        }
    }

    @ViewBuilder private var photoPreview: some View {
        if let image = pendingPhoto {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(Circle())
        } else {
            OccasionAvatar(occasion: draft, size: 64, emojiSize: 34)
                .background(Theme.gradient(draft.palette), in: Circle())
        }
    }

    private var emojiSection: some View {
        Section("Emoji") {
            Text(draft.displayEmoji)
                .font(.system(size: 44))
                .frame(maxWidth: .infinity)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Theme.emojiChoices, id: \.self) { e in
                        Chip(e, isSelected: draft.emoji == e, font: Theme.font(24)) {
                            draft.emoji = e
                        }
                    }
                }
            }
            TextField("Or type any emoji", text: $emojiText)
                .onChange(of: emojiText) { _, newValue in
                    if let last = newValue.last {
                        draft.emoji = String(last)
                    }
                }
        }
    }

    private var colorSection: some View {
        Section("Color") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(OccasionPalette.allCases, id: \.self) { p in
                        Button {
                            draft.palette = p
                        } label: {
                            Circle()
                                .fill(Theme.gradient(p))
                                .frame(width: 34, height: 34)
                                .overlay {
                                    Circle().stroke(Color.primary, lineWidth: draft.palette == p ? 3 : 0)
                                }
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(p.rawValue.capitalized)
                        .accessibilityAddTraits(draft.palette == p ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var whenSection: some View {
        Section {
            Picker("Month", selection: $draft.month) {
                ForEach(1...12, id: \.self) { m in
                    Text(OccasionMath.monthName(m, calendar: .current)).tag(m)
                }
            }
            .pickerStyle(.menu)
            Picker("Day", selection: $draft.day) {
                ForEach(1...OccasionMath.daysInMonth(draft.month), id: \.self) { d in
                    Text(String(d)).tag(d)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: draft.month) { _, m in
                draft.day = min(draft.day, OccasionMath.daysInMonth(m))
            }
            Toggle("Repeats every year", isOn: $repeatsYearly)
                .onChange(of: repeatsYearly) { _, repeats in
                    let current = OccasionEditorView.currentYear()
                    year = repeats ? min(year, current) : max(year, current)
                }
            if repeatsYearly {
                Toggle("Include year", isOn: $includeYear)
            }
            if includeYear || !repeatsYearly {
                Picker("Year", selection: $year) {
                    ForEach(years, id: \.self) { y in
                        Text(String(y)).tag(y)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
            }
        } header: {
            Text("When")
        } footer: {
            Text(repeatsYearly
                 ? "Add the year to see “turns 30” or “5th anniversary”."
                 : "Happens once, like a trip. After the day it moves to Past.")
        }
    }

    private var chipOffsets: [Int] {
        return Array(Set(Occasion.presetReminderOffsets + draft.reminderOffsets)).sorted(by: >)
    }

    private var remindSection: some View {
        Section("Remind me") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chipOffsets, id: \.self) { o in
                        Chip(OccasionMath.offsetLabel(o), isSelected: draft.reminderOffsets.contains(o)) {
                            toggleOffset(o)
                        }
                    }
                }
            }
            HStack {
                TextField("Days before", value: $customDays, format: .number)
                    .keyboardType(.numberPad)
                    .focused($customFocused)
                Button("Add") { addCustom() }
            }
            DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
        }
    }

    private var noteSection: some View {
        Section("Note") {
            TextField("Gift ideas, plans, anything", text: $draft.note, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private func selectKind(_ kind: OccasionKind) {
        if draft.emoji == draft.kind.defaultEmoji {
            draft.emoji = kind.defaultEmoji
        }
        draft.kind = kind
    }

    private func toggleOffset(_ offset: Int) {
        if let index = draft.reminderOffsets.firstIndex(of: offset) {
            draft.reminderOffsets.remove(at: index)
        } else {
            draft.reminderOffsets.append(offset)
        }
    }

    private func addCustom() {
        if (1...365).contains(customDays) && !draft.reminderOffsets.contains(customDays) {
            draft.reminderOffsets.append(customDays)
        }
        customFocused = false
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item = item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return
        }
        // Cleared so picking the same photo again still fires onChange.
        photoItem = nil
        cropRequest = CropRequest(image: PhotoSizing.downscaled(image, maxSide: PhotoSizing.fullMaxSide), isNewPhoto: true)
    }

    /// Re-frame from the whole photo: the one just picked, else the saved one.
    /// Dates saved before full photos were kept can only zoom into their square.
    private func adjustPhoto() {
        if let full = pendingFull {
            cropRequest = CropRequest(image: full, isNewPhoto: true)
            return
        }
        guard let url = store.fullPhotoURL(for: draft), let saved = UIImage(contentsOfFile: url.path) else {
            return
        }
        cropRequest = CropRequest(image: saved, isNewPhoto: false)
    }

    private func removePhoto() {
        pendingPhoto = nil
        pendingFull = nil
        photoItem = nil
        draft.photoFileName = nil
        draft.photoFullFileName = nil
    }

    private func save() {
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.year = (includeYear || !repeatsYearly) ? year : nil
        draft.oneTime = repeatsYearly ? nil : true
        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        draft.reminderHour = comps.hour ?? AppDefaults.defaultReminderHour
        draft.reminderMinute = comps.minute ?? AppDefaults.defaultReminderMinute
        draft.reminderOffsets = draft.reminderOffsets.sorted(by: >)
        // Once the user edits an example it is their own date, so it takes a free slot.
        draft.isSample = nil
        if let image = pendingPhoto,
           let data = image.jpegData(compressionQuality: 0.85),
           let name = store.savePhoto(data) {
            draft.photoFileName = name
        }
        if let full = pendingFull,
           let data = full.jpegData(compressionQuality: 0.85),
           let name = store.savePhoto(data) {
            draft.photoFullFileName = name
        }
        onSave(draft)
        dismiss()
    }
}

/// What the cropper is opened with. `isNewPhoto` says whether its image should be
/// saved as the date's whole photo once framed.
private struct CropRequest: Identifiable {
    let id: UUID = UUID()
    let image: UIImage
    let isNewPhoto: Bool
}
