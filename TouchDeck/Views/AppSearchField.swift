import SwiftUI

/// iOS 검색창처럼 생긴 입력칸. 돋보기, 지우기 버튼, 키보드의 "검색" 키.
struct AppSearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("앱 이름, 영어 이름, 초성(ㅁㅁ)으로 검색", text: $text)
                .focused(focused)
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("앱 검색")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("검색어 지우기")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 12))
    }
}
