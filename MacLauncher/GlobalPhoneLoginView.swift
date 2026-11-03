import SwiftUI

struct GlobalPhoneLoginView: View {
    @Environment(\.dismiss) private var dismiss

    var onSignedIn: (String) -> Void = { _ in }

    private let countryCodes = [
        ("中国大陆", "+86"),
        ("澳大利亚", "+61"),
        ("美国/加拿大", "+1"),
        ("英国", "+44"),
        ("日本", "+81"),
        ("新加坡", "+65"),
        ("中国香港", "+852")
    ]

    @State private var selectedCode = "+86"
    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    @State private var isCodeSent = false
    @State private var isLoading = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)

                Text("Vesta 全球手机号登录")
                    .font(.title3.bold())

                Text("支持全球主流国家及地区短信验证")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Picker("区号", selection: $selectedCode) {
                        ForEach(countryCodes, id: \.1) { name, code in
                            Text("\(name) (\(code))").tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 168)
                    .disabled(isCodeSent)

                    TextField("手机号码", text: $phoneNumber)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isCodeSent)
                        .onChange(of: phoneNumber) { _, newValue in
                            let digits = newValue.filter(\.isNumber)
                            if digits != newValue {
                                phoneNumber = digits
                            }
                        }
                }

                if isCodeSent {
                    TextField("请输入 6 位短信验证码", text: $verificationCode)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: verificationCode) { _, newValue in
                            let digits = String(newValue.filter(\.isNumber).prefix(6))
                            if digits != newValue {
                                verificationCode = digits
                            }
                        }

                    Button(action: verifySmsCode) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("验证并登录 Vesta")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(isLoading || verificationCode.count != 6)

                    Button("更换号码") {
                        isCodeSent = false
                        verificationCode = ""
                        errorMessage = ""
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Button(action: sendSmsVerification) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("获取国际短信验证码")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(isLoading || phoneNumber.isEmpty)
                }
            }
            .padding(.horizontal)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            Button("取消") {
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 440, height: 420)
    }

    private func sendSmsVerification() {
        isLoading = true
        errorMessage = ""

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isLoading = false
            isCodeSent = true
        }
    }

    private func verifySmsCode() {
        isLoading = true
        errorMessage = ""

        let fullPhoneNumber = "\(selectedCode) \(phoneNumber)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isLoading = false
            if verificationCode.count == 6, verificationCode.allSatisfy(\.isNumber) {
                onSignedIn(fullPhoneNumber)
                dismiss()
            } else {
                errorMessage = "验证码错误，请输入 6 位数字"
            }
        }
    }
}

#Preview {
    GlobalPhoneLoginView()
}
