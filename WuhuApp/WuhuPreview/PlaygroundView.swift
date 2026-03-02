import Inject
import SwiftUI

struct PlaygroundView: View {
  @ObserveInjection var inject

  var body: some View {
    VStack(spacing: 24) {
      RoundedRectangle(cornerRadius: 24)
        .fill(.purple.gradient)
        .frame(width: 200, height: 200)
        .overlay {
          Text("🔥")
            .font(.system(size: 80))
        }

      Text("ATTEMPT #7")
        .font(.title.bold())
        .foregroundStyle(.red)

      Text("Live from the CLI")
        .font(.headline)
        .foregroundStyle(.secondary)
    }
    .enableInjection()
  }
}
