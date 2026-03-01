import SwiftUI

#if os(iOS)
struct SplashScreenView: View {
    let onFinished: () -> Void

    @State private var iconScale: CGFloat = 0.5
    @State private var iconOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var dismissOpacity: Double = 1

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 52))
                    .foregroundStyle(.purple.gradient)
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)

                Text("Local MLX")
                    .font(.title)
                    .fontWeight(.bold)
                    .opacity(textOpacity)
            }
        }
        .opacity(dismissOpacity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                iconScale = 1.0
                iconOpacity = 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeIn(duration: 0.3)) {
                    textOpacity = 1
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    dismissOpacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onFinished()
                }
            }
        }
    }
}
#endif
