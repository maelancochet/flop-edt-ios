import SwiftUI

struct LogoView: View {
    @AppStorage("version") var version: String = "25.11.6-beta"
    
    var body: some View {
        VStack{
            Spacer()
                
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 95+90, height: 110+90)
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1)
            
            Spacer()
            Text(version)
                .font(.caption)
                .foregroundColor(.white)
            Text("@m3_maelan")
                .font(.caption)
                .foregroundColor(.white)
                
        }
        .containerRelativeFrame([.horizontal, .vertical])
        .background(.mainBackground)
        .padding()
    }
}

#Preview {
    LogoView()
}
