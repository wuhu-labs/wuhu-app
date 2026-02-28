import SwiftUI

#if os(iOS)
  import PhotosUI
#endif

/// A multi-line chat input field that sends on ⌘Enter and inserts newlines on
/// bare Enter. Always shows at least 3 lines of height with a placeholder
/// overlay when the draft is empty.
///
/// An optional `toolbar` view is rendered above the text editor inside the
/// input area (e.g. a lane picker).
///
/// Supports image attachments via `pendingImages`. On iOS, images are picked
/// using `PhotosPicker`; on macOS, a file open panel is used.
struct ChatInputField<Toolbar: View>: View {
  @Binding var draft: String
  var placeholder: String = "Message..."
  var pendingImages: [PendingImage] = []
  var isUploadingImages: Bool = false
  var onSend: () -> Void
  var onAddImage: ((Data, String) -> Void)?
  var onRemoveImage: ((UUID) -> Void)?
  @ViewBuilder var toolbar: Toolbar

  #if os(iOS)
    @State private var selectedPhotos: [PhotosPickerItem] = []
  #endif

  /// Approximate height of a single line of body text.
  private let lineHeight: CGFloat = 20
  /// Minimum visible lines when the field is empty.
  private let minLines = 3
  /// Maximum lines before the editor stops growing.
  private let maxLines = 10

  private var canSend: Bool {
    !draft.isEmpty || !pendingImages.isEmpty
  }

  private static var supportedTypes: [String] {
    ["png", "jpg", "jpeg", "gif", "webp"]
  }

  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      VStack(alignment: .leading, spacing: 4) {
        toolbar

        // Pending image thumbnails
        if !pendingImages.isEmpty {
          pendingImageStrip
        }

        ZStack(alignment: .topLeading) {
          TextEditor(text: $draft)
            .font(.body)
            .scrollContentBackground(.hidden)
            .frame(
              minHeight: lineHeight * CGFloat(minLines),
              maxHeight: lineHeight * CGFloat(maxLines),
            )
            .fixedSize(horizontal: false, vertical: true)
            .onKeyPress(.return, phases: .down) { press in
              if press.modifiers.contains(.command) {
                onSend()
                return .handled
              }
              return .ignored
            }

          // Placeholder overlay
          if draft.isEmpty && pendingImages.isEmpty {
            Text("⌘Enter to send · Enter for newline")
              .foregroundStyle(.tertiary)
              .font(.body)
              .padding(.horizontal, 5)
              .padding(.vertical, 8)
              .allowsHitTesting(false)
          }
        }
      }
      .padding(6)
      .background(.background.secondary)
      .clipShape(RoundedRectangle(cornerRadius: 8))

      VStack(spacing: 6) {
        imagePickerButton

        Button {
          onSend()
        } label: {
          if isUploadingImages {
            ProgressView()
              .controlSize(.small)
              .frame(width: 28, height: 28)
          } else {
            Image(systemName: "arrow.up.circle.fill")
              .font(.title2)
              .foregroundStyle(canSend ? .orange : .gray)
          }
        }
        .buttonStyle(.plain)
        .disabled(!canSend || isUploadingImages)
      }
    }
    .padding(12)
  }

  // MARK: - Pending Image Strip

  private var pendingImageStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(pendingImages) { img in
          PendingImageThumbnail(image: img, onRemove: {
            onRemoveImage?(img.id)
          })
        }
      }
      .padding(.vertical, 4)
    }
  }

  // MARK: - Image Picker Button

  @ViewBuilder
  private var imagePickerButton: some View {
    #if os(iOS)
      PhotosPicker(
        selection: $selectedPhotos,
        maxSelectionCount: 10,
        matching: .images,
      ) {
        Image(systemName: "photo.badge.plus")
          .font(.title3)
          .foregroundStyle(.orange)
      }
      .buttonStyle(.plain)
      .onChange(of: selectedPhotos) { _, newItems in
        Task {
          for item in newItems {
            if let data = try? await item.loadTransferable(type: Data.self) {
              let mimeType = mimeTypeForPhotosItem(item)
              onAddImage?(data, mimeType)
            }
          }
          selectedPhotos = []
        }
      }
    #else
      Button {
        openFilePickerMacOS()
      } label: {
        Image(systemName: "photo.badge.plus")
          .font(.title3)
          .foregroundStyle(.orange)
      }
      .buttonStyle(.plain)
      .help("Attach images")
    #endif
  }

  // MARK: - Platform-Specific Helpers

  #if os(iOS)
    private func mimeTypeForPhotosItem(_ item: PhotosPickerItem) -> String {
      if let contentType = item.supportedContentTypes.first {
        if contentType.conforms(to: .png) { return "image/png" }
        if contentType.conforms(to: .gif) { return "image/gif" }
        if contentType.conforms(to: .webP) { return "image/webp" }
      }
      return "image/jpeg"
    }
  #endif

  #if os(macOS)
    private func openFilePickerMacOS() {
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = true
      panel.canChooseDirectories = false
      panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
      panel.message = "Select images to attach"

      guard panel.runModal() == .OK else { return }
      for url in panel.urls {
        if let data = try? Data(contentsOf: url) {
          let mimeType = mimeTypeForExtension(url.pathExtension.lowercased())
          onAddImage?(data, mimeType)
        }
      }
    }

    private func mimeTypeForExtension(_ ext: String) -> String {
      switch ext {
      case "png": "image/png"
      case "gif": "image/gif"
      case "webp": "image/webp"
      case "jpg", "jpeg": "image/jpeg"
      default: "image/jpeg"
      }
    }
  #endif
}

// MARK: - Pending Image Thumbnail

private struct PendingImageThumbnail: View {
  let image: PendingImage
  var onRemove: () -> Void

  var body: some View {
    ZStack(alignment: .topTrailing) {
      thumbnailImage
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 6))

      Button(action: onRemove) {
        Image(systemName: "xmark.circle.fill")
          .font(.caption)
          .foregroundStyle(.white)
          .background(Circle().fill(.black.opacity(0.6)))
      }
      .buttonStyle(.plain)
      .offset(x: 4, y: -4)
    }
  }

  @ViewBuilder
  private var thumbnailImage: some View {
    #if os(iOS)
      if let uiImage = UIImage(data: image.data) {
        Image(uiImage: uiImage)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        imagePlaceholder
      }
    #else
      if let nsImage = NSImage(data: image.data) {
        Image(nsImage: nsImage)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        imagePlaceholder
      }
    #endif
  }

  private var imagePlaceholder: some View {
    Rectangle()
      .fill(.quaternary)
      .overlay {
        Image(systemName: "photo")
          .foregroundStyle(.secondary)
      }
  }
}

// MARK: - Convenience Initialisers

extension ChatInputField where Toolbar == EmptyView {
  /// Convenience initialiser with no toolbar.
  init(
    draft: Binding<String>,
    placeholder: String = "Message...",
    pendingImages: [PendingImage] = [],
    isUploadingImages: Bool = false,
    onSend: @escaping () -> Void,
    onAddImage: ((Data, String) -> Void)? = nil,
    onRemoveImage: ((UUID) -> Void)? = nil,
  ) {
    _draft = draft
    self.placeholder = placeholder
    self.pendingImages = pendingImages
    self.isUploadingImages = isUploadingImages
    self.onSend = onSend
    self.onAddImage = onAddImage
    self.onRemoveImage = onRemoveImage
    toolbar = EmptyView()
  }
}
