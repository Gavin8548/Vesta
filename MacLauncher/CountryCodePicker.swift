//
//  CountryCodePicker.swift
//
//  手机号登录用的国家区号。标识按国家名称固定，不使用每次刷新都会变化的 UUID。
//

import SwiftUI

struct CountryCode: Identifiable, Hashable {
    let region: String
    let nameZh: String
    let nameEn: String
    let code: String
    let flag: String

    var id: String { "\(region)|\(code)" }

    func displayName(for language: AppLanguage) -> String {
        language == .chinese ? nameZh : nameEn
    }

    static func find(code: String, nameZh: String) -> CountryCode {
        all.first { $0.code == code && $0.nameZh == nameZh } ?? preferred
    }

    static var preferred: CountryCode {
        let region = Locale.current.region?.identifier ?? ""
        return all.first { $0.region == region } ?? all.first { $0.region == "AU" } ?? all[0]
    }

    static let all: [CountryCode] = [
        CountryCode(region: "CN", nameZh: "中国大陆", nameEn: "China", code: "+86", flag: "🇨🇳"),
        CountryCode(region: "HK", nameZh: "中国香港", nameEn: "Hong Kong", code: "+852", flag: "🇭🇰"),
        CountryCode(region: "MO", nameZh: "中国澳门", nameEn: "Macao", code: "+853", flag: "🇲🇴"),
        CountryCode(region: "TW", nameZh: "中国台湾", nameEn: "Taiwan", code: "+886", flag: "🇹🇼"),
        CountryCode(region: "US", nameZh: "美国 / 加拿大", nameEn: "United States / Canada", code: "+1", flag: "🇺🇸"),
        CountryCode(region: "AU", nameZh: "澳大利亚", nameEn: "Australia", code: "+61", flag: "🇦🇺"),
        CountryCode(region: "GB", nameZh: "英国", nameEn: "United Kingdom", code: "+44", flag: "🇬🇧"),
        CountryCode(region: "JP", nameZh: "日本", nameEn: "Japan", code: "+81", flag: "🇯🇵"),
        CountryCode(region: "SG", nameZh: "新加坡", nameEn: "Singapore", code: "+65", flag: "🇸🇬"),
        CountryCode(region: "KR", nameZh: "韩国", nameEn: "South Korea", code: "+82", flag: "🇰🇷"),
        CountryCode(region: "DE", nameZh: "德国", nameEn: "Germany", code: "+49", flag: "🇩🇪"),
        CountryCode(region: "FR", nameZh: "法国", nameEn: "France", code: "+33", flag: "🇫🇷"),
        CountryCode(region: "NZ", nameZh: "新西兰", nameEn: "New Zealand", code: "+64", flag: "🇳🇿"),
        CountryCode(region: "MY", nameZh: "马来西亚", nameEn: "Malaysia", code: "+60", flag: "🇲🇾"),
        CountryCode(region: "CA", nameZh: "加拿大", nameEn: "Canada", code: "+1", flag: "🇨🇦"),
        CountryCode(region: "IN", nameZh: "印度", nameEn: "India", code: "+91", flag: "🇮🇳"),
        CountryCode(region: "RU", nameZh: "俄罗斯", nameEn: "Russia", code: "+7", flag: "🇷🇺"),
        CountryCode(region: "IT", nameZh: "意大利", nameEn: "Italy", code: "+39", flag: "🇮🇹"),
        CountryCode(region: "ES", nameZh: "西班牙", nameEn: "Spain", code: "+34", flag: "🇪🇸"),
        CountryCode(region: "NL", nameZh: "荷兰", nameEn: "Netherlands", code: "+31", flag: "🇳🇱"),
        CountryCode(region: "CH", nameZh: "瑞士", nameEn: "Switzerland", code: "+41", flag: "🇨🇭"),
        CountryCode(region: "SE", nameZh: "瑞典", nameEn: "Sweden", code: "+46", flag: "🇸🇪"),
        CountryCode(region: "VN", nameZh: "越南", nameEn: "Vietnam", code: "+84", flag: "🇻🇳"),
        CountryCode(region: "TH", nameZh: "泰国", nameEn: "Thailand", code: "+66", flag: "🇹🇭")
    ]
}

struct GlobalCountryPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageManager
    @Binding var selectedCode: String
    @Binding var selectedCountryName: String
    @State private var searchText = ""

    private var filteredCountries: [CountryCode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return CountryCode.all }
        return CountryCode.all.filter { country in
            country.nameZh.localizedCaseInsensitiveContains(query)
                || country.nameEn.localizedCaseInsensitiveContains(query)
                || country.code.contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TextField(language.text(.countrySearchPrompt), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding()
            List(filteredCountries) { country in
                countryRow(country)
            }
        }
        .frame(width: 360, height: 420)
    }

    private var header: some View {
        HStack {
            Text(language.text(.chooseCountry))
                .font(.headline)
            Spacer()
            Button(language.text(.close)) { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    private func countryRow(_ country: CountryCode) -> some View {
        Button {
            selectedCode = country.code
            selectedCountryName = country.nameZh
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(country.flag)
                    .font(.title2)
                Text(country.displayName(for: language.currentLanguage))
                    .foregroundStyle(.primary)
                Spacer()
                Text(country.code)
                    .foregroundStyle(.secondary)
                    .bold()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

struct PhoneNumberLoginForm: View {
    @EnvironmentObject private var language: LanguageManager
    @Binding var selectedCountryName: String
    @Binding var selectedCode: String
    @Binding var phoneNumber: String
    var onRequestCode: () -> Void

    @State private var showCountryPicker = false

    private var selectedCountry: CountryCode {
        CountryCode.find(code: selectedCode, nameZh: selectedCountryName)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(language.text(.phoneLoginTitle))
                .font(.title3.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                countryButton
                TextField(language.text(.authPhonePlaceholder), text: $phoneNumber)
                    .textFieldStyle(.roundedBorder)
            }
            Button(language.text(.authGetCode), action: onRequestCode)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var countryButton: some View {
        Button {
            showCountryPicker = true
        } label: {
            HStack {
                Text("\(selectedCountry.displayName(for: language.currentLanguage)) (\(selectedCountry.code))")
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(width: 180)
        .sheet(isPresented: $showCountryPicker) {
            GlobalCountryPickerView(selectedCode: $selectedCode, selectedCountryName: $selectedCountryName)
                .environmentObject(language)
        }
    }
}
