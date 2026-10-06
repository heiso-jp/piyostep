import SwiftUI
import PiyoCore

/// 文字・数字ひとつずつの習熟度を表で見せる。
///
/// 「あ は読めるが書けない」まで見えるように、よみ / かき を分けて出す。
/// なぞり書きはお手本をなぞるだけで評価にならないため、かきは自由書きのみを数えている。
struct ItemMasterySection: View {
    @Bindable var model: ParentDashboardViewModel

    @State private var category: LearningItemID.Category = .hiragana

    private var items: [LearningItemID] { model.items(in: category) }
    private var abilities: [LearningAbility] { model.abilities(in: category) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("もじ・すうじ の しゅうじゅく度")
                .font(.headline)

            Picker("カテゴリ", selection: $category) {
                ForEach(LearningItemID.Category.allCases, id: \.self) { category in
                    Text(category.parentTitle).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(A11yID.parentItemMasteryPicker)

            averageRow

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92), spacing: 10)],
                spacing: 10
            ) {
                ForEach(items) { item in
                    cell(item)
                }
            }

            Text(footnote)
                .font(.caption2)
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .accessibilityIdentifier(A11yID.parentItemMastery)
    }

    private var averageRow: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text(LearningAbility.read.parentTitle)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                if let average = model.averagePercent(for: category, ability: .read) {
                    Text("\(average)%")
                        .font(.headline)
                        .monospacedDigit()
                } else {
                    Text("—")
                        .font(.headline)
                        .foregroundStyle(Color.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func cell(_ item: LearningItemID) -> some View {
        let read = model.mastery(for: item, ability: .read)
        let write = model.mastery(for: item, ability: .write)
        let practice = model.practiceCount(for: item)

        return VStack(spacing: 6) {
            Text(item.value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(read == nil ? Color.secondary : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            HStack(spacing: 4) {
                Text(LearningAbility.read.parentTitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
                Spacer(minLength: 0)
                Text(read.map { "\($0.percent)" } ?? "–")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(color(for: read))
            }

            // かきは回数だけ出す。形の評価はまだ精度が足りず、
            // パーセントにすると「書けている」と誤解させてしまう。
            if abilities.contains(.write) {
                HStack(spacing: 4) {
                    Text(LearningAbility.write.parentTitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                    Spacer(minLength: 0)
                    Text(writeCountText(write: write, practice: practice))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(background(for: read))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(item: item, read: read, write: write))
    }

    /// かきの回数。自由書きとなぞりを合わせた「やった回数」。
    private func writeCountText(write: ItemMastery?, practice: Int) -> String {
        let total = (write?.attempts ?? 0) + practice
        return total == 0 ? "–" : "\(total)かい"
    }

    /// 未実施はグレー、低いほど赤寄り、高いほど緑寄り。
    private func color(for mastery: ItemMastery?) -> Color {
        guard let mastery, mastery.attempts > 0 else { return .secondary }
        switch mastery.percent {
        case 80...: return .green
        case 50 ..< 80: return .orange
        default: return .red
        }
    }

    private func background(for read: ItemMastery?) -> Color {
        guard let read, read.attempts > 0 else {
            return Color(.tertiarySystemGroupedBackground)
        }
        return color(for: read).opacity(0.12)
    }

    private func accessibilityLabel(
        item: LearningItemID,
        read: ItemMastery?,
        write: ItemMastery?
    ) -> String {
        var parts = [item.value]
        if let read { parts.append("よみ \(read.percent)パーセント") }
        if let write { parts.append("かき \(write.percent)パーセント") }
        if parts.count == 1 { parts.append("まだ やっていません") }
        return parts.joined(separator: "、")
    }

    private var footnote: String {
        category == .number
            ? "数字は「よみ」のみ記録しています。1回で正解すると100%、まちがえると下がります。"
            : "「かき」は やった回数だけを出しています。書けた形を 正しく評価する仕組みが未完成のため、割合は出していません。"
    }
}
