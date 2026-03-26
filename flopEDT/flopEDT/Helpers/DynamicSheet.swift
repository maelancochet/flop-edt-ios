import SwiftUI

struct DynamicSheet<Content: View>: View {
    var animation: Animation
    @ViewBuilder var content: Content
    @State private var sheetHeight: CGFloat = 0
    @State private var isVisible: Bool = {
        if #available(iOS 18, *) {
            return true
        }
        return false
    }()
    var body: some View {
        ZStack {
            content
                /// As this will fix the size of the view in the vertical direction!
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGSize.self) {
                    isVisible ? $0.size : .zero
                } action: { newValue in
                    guard newValue != .zero else { return }
                    
                    if sheetHeight == .zero {
                        /// Customize it according to your needs!
                        sheetHeight = min(newValue.height, windowSize.height - 110)
                    } else {
                        withAnimation(animation) {
                            sheetHeight = min(newValue.height, windowSize.height - 110)
                        }
                    }
                }
                .task { isVisible = true }
        }
        .modifier(SheetHeightModifier(height: sheetHeight))
        .preferredColorScheme(.dark)
    }
    
    /// You can use property to limit the max height, but I'm using the window size height to do so!
    var windowSize: CGSize {
        if let size = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.size{
            return size
        }
        
        return .zero
    }
}

fileprivate struct SheetHeightModifier: ViewModifier, Animatable {
    var height: CGFloat
    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }
    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26, *) {
                content
            } else {
                content
                    .clipShape(.rect(cornerRadius: 30, style: .continuous))
                    .background {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(.background)
                            .frame(height: height)
                    }
                    .padding(.horizontal, 15)
                    .presentationBackground(.clear)
                    .presentationCornerRadius(0)
            }
        }
        .presentationDetents(height == .zero ? [.medium] : [.height(height)])
    }
}

#Preview {
    ContentView()
}
