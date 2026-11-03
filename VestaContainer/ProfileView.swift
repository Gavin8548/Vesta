//
//  ProfileView.swift
//
//  昵称按用户输入原样保存，不移除特殊符号。
//

import AppKit
import PhotosUI
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var language: LanguageManager
    @ObservedObject private var account = SupabaseManager.shared
    @State private var username = ""
    @State private var birthday = Date()
    @State private var avatarData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var statusMessage = ""
    @State private var statusIsError = false
    @State private var isSaving = false
    @State private var needsSignIn = false

    var body: some View {
        Section(language.text(.profileTitle)) {
            avatarRow
            TextField(language.text(.profileUsernamePrompt), text: $username)
            DatePicker(language.text(.profileBirthday), selection: $birthday, displayedComponents: .date)
            Button(language.text(.profileSave)) {
                Task { await save() }
            }
            .disabled(isSaving || needsSignIn)
            if isSaving {
                ProgressView()
                    .controlSize(.small)
            }
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusIsError ? Color.red : Color.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await load() }
    }

    private var avatarRow: some View {
        let chooseTitle = language.text(.profileChoosePhoto)
        return HStack(spacing: 12) {
            avatarPreview
            PhotosPicker(selection: $photoItem, matching: .images) {
                Text(chooseTitle)
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let avatarData, let image = NSImage(data: avatarData) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(Circle())
        } else if let url = account.profile?.avatarUrl.flatMap(URL.init(string:)) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholderAvatar
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())
        } else {
            placeholderAvatar
        }
    }

    private var placeholderAvatar: some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.system(size: 64))
            .foregroundStyle(.orange)
    }

    private func load() async {
        do {
            if let profile = try await account.fetchProfile() {
                username = profile.username ?? ""
                if let day = profile.birthday {
                    birthday = day
                }
                needsSignIn = false
            }
        } catch {
            needsSignIn = true
            statusMessage = language.text(.profileSignInFirst)
            statusIsError = true
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let picked = try await item.loadTransferable(type: PickedProfileImage.self) else { return }
            avatarData = picked.data
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await account.updateProfile(username: username, birthday: birthday, avatarData: avatarData)
            statusMessage = language.text(.profileSaved)
            statusIsError = false
            needsSignIn = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }
}

private struct PickedProfileImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            PickedProfileImage(data: data)
        }
    }
}
