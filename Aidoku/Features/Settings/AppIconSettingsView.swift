//
//  AppIconSettingsView.swift
//  Aidoku
//

import SwiftUI
import UIKit

@MainActor
struct AppIconSettingsView: View {
    @State private var selectedIconName = UIApplication.shared.alternateIconName
    @State private var isUpdating = false
    @State private var errorMessage = ""
    @State private var showError = false

    var body: some View {
        HStack(spacing: 48) {
            iconOption(title: "Kanji", imageName: "KanjiIconPreview", iconName: nil)
            iconOption(title: "Mihon", imageName: "MihonIconPreview", iconName: "Mihon")
            iconOption(title: "Books", imageName: "BooksIconPreview", iconName: "Books")
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            selectedIconName = UIApplication.shared.alternateIconName
        }
        .alert("Unable to Change Icon", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func iconOption(title: String, imageName: String, iconName: String?) -> some View {
        let selected = selectedIconName == iconName
        return Button {
            selectIcon(iconName)
        } label: {
            VStack(spacing: 10) {
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)

                Text(title)
                    .foregroundStyle(Color(uiColor: .label))

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(Color(uiColor: selected ? .tintColor : .secondarySystemFill))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isUpdating)
        .accessibilityValue(selected ? "Selected" : "")
    }

    private func selectIcon(_ iconName: String?) {
        guard !isUpdating, selectedIconName != iconName else { return }
        guard UIApplication.shared.supportsAlternateIcons else {
            errorMessage = "This app build does not support alternate icons."
            showError = true
            return
        }

        isUpdating = true
        UIApplication.shared.setAlternateIconName(iconName) { error in
            Task { @MainActor in
                isUpdating = false
                selectedIconName = UIApplication.shared.alternateIconName
                if let error {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}
