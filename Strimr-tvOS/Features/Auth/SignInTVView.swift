import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct SignInTVView: View {
    @State private var viewModel: SignInTVViewModel
    @FocusState private var focusedField: SignInField?

    private enum SignInField: Hashable {
        case email, password, signInButton
    }

    private let ciContext = CIContext()

    init(viewModel: SignInTVViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left side — branding
            VStack(spacing: 16) {
                Spacer()
                Image(.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 192, height: 192)
                Text("signIn.title")
                    .font(.largeTitle.bold())
                Text("signIn.tv.subtitle")
                    .foregroundStyle(.secondary)
                    .font(.title3)
                Spacer()
            }
            .frame(maxWidth: .infinity)

            // Right side — sign in methods
            VStack {
                Spacer()

                Picker("", selection: $viewModel.signInMethod) {
                    ForEach(SignInMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 400)
                .padding(.bottom, 32)
                .onChange(of: viewModel.signInMethod) {
                    viewModel.cancelSignIn()
                    viewModel.errorMessage = nil
                }

                Group {
                    switch viewModel.signInMethod {
                    case .credentials:
                        credentialsView
                    case .qrCode:
                        qrCodeView
                    }
                }
                .frame(width: 500)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .padding(.top, 16)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(48)
        .onDisappear { viewModel.cancelSignIn() }
    }

    // MARK: - Email/Password

    private var credentialsView: some View {
        VStack(spacing: 24) {
            TextField("Email", text: $viewModel.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .email)
                .onSubmit {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusedField = .password
                    }
                }

            SecureField("Password", text: $viewModel.password)
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .onSubmit {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusedField = .signInButton
                    }
                }

            Button {
                Task { await viewModel.signInWithCredentials() }
            } label: {
                if viewModel.isAuthenticating {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Sign In")
                        .frame(maxWidth: .infinity)
                }
            }
            .focused($focusedField, equals: .signInButton)
            .disabled(viewModel.isAuthenticating || viewModel.email.isEmpty || viewModel.password.isEmpty)
        }
    }

    // MARK: - QR Code

    private var qrCodeView: some View {
        VStack(spacing: 20) {
            if let pin = viewModel.pin,
               let url = qrURL(pin: pin),
               let qrImage = qrImage(from: url.absoluteString)
            {
                Image(uiImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 240, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Scan with your phone to sign in")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                if viewModel.isAuthenticating {
                    ProgressView("Waiting for sign in...")
                }
            } else if viewModel.isAuthenticating {
                ProgressView("Loading...")
            } else {
                Button("Show QR Code") {
                    Task { await viewModel.startQRSignIn() }
                }
            }
        }
        .onAppear {
            if viewModel.pin == nil, !viewModel.isAuthenticating {
                Task { await viewModel.startQRSignIn() }
            }
        }
    }
}

extension SignInTVView {
    private func qrImage(from string: String) -> UIImage? {
        guard let data = string.data(using: .ascii) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))

        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func qrURL(pin: PlexCloudPin) -> URL? {
        let base = "https://app.plex.tv/auth#?"
        let fragment =
            "clientID=\(pin.clientIdentifier)" +
            "&context%5Bdevice%5D%5Bproduct%5D=Strimr" +
            "&code=\(pin.code)"

        return URL(string: base + fragment)
    }
}
