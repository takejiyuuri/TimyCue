import CoreLocation
import SwiftUI

/// 場所の候補を探して 1 つ選ぶ（「場所を確認」Q66・自宅の登録 spec Q42-2）。
/// 候補の一覧と検索だけ。お気に入りや細かな場所の管理は作らない（2026-10-14 決定）
struct PlaceSearchView: View {
    let title: String
    var near: CLLocationCoordinate2D?
    let onSelect: (MapPlaceResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var candidates: [MapPlaceResult] = []
    @State private var isSearching = false

    init(title: String, initialQuery: String, near: CLLocationCoordinate2D? = nil, onSelect: @escaping (MapPlaceResult) -> Void) {
        self.title = title
        self.near = near
        self.onSelect = onSelect
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("場所の名前・住所", text: $query)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                }
                Section {
                    if isSearching {
                        ProgressView()
                    } else if candidates.isEmpty && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("候補が見つかりません")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    ForEach(candidates) { candidate in
                        Button {
                            onSelect(candidate)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.name)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                if let address = candidate.address {
                                    Text(address)
                                        .font(.footnote)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("候補")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            // 打つのが少し止まってから探す
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                isSearching = true
                candidates = await PlaceSearch.search(query, near: near)
                isSearching = false
            }
        }
    }
}
