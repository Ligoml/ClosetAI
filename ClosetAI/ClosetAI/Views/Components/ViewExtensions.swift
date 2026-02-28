import SwiftUI

// MARK: - Keyboard Dismiss Helper

extension UIApplication {
    static func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}

// MARK: - Error Toast Modifier

/// 在视图底部以红色 Capsule 弹出错误消息，3.5 秒后自动消失，点击可手动关闭。
/// 用法：.errorToast($viewModel.errorMessage)
struct ErrorToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            if let msg = message {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                    Text(msg)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(
                    Capsule()
                        .fill(Color(red: 0.85, green: 0.2, blue: 0.2).opacity(0.92))
                        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 4)
                )
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture {
                    withAnimation { message = nil }
                }
                .onAppear {
                    let captured = msg
                    Task {
                        try? await Task.sleep(nanoseconds: 3_500_000_000)
                        // 只有消息未被手动清除时才自动关闭
                        if message == captured {
                            withAnimation { message = nil }
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: message)
    }
}

extension View {
    func errorToast(_ message: Binding<String?>) -> some View {
        modifier(ErrorToastModifier(message: message))
    }
}
