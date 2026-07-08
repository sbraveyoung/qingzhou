import SwiftUI
import QingzhouCore

/// 「当前节点疑似故障」红色横幅 + 一键「切换到最优节点」（首页顶部）。
///
/// 触发：特性开（FeatureFlags + 用户 opt-in 设置）且读到扩展写的新鲜 `.suspect` 信号
/// （见 `AppState.syncNodeHealth`）。点按钮走 `AppState.failoverToBestNode`（排除疑似节点 →
/// 现有打分选最优 → 原地换出口）。保守 MVP：只提示 + 用户一键，不自动切数据面。
struct FailoverBanner: View {
    @Bindable var state: AppState
    @State private var switching = false

    /// 是否应显示：编译期总开关 + 用户 opt-in + 有新鲜 suspect 信号。
    static func shouldShow(state: AppState) -> Bool {
        FeatureFlags.autoFailoverAlert
            && state.settings.autoFailoverAlert
            && state.nodeHealthSuspect != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text("当前节点疑似故障")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.white)
                Text("代理上行还在发、下行却没有回流。可一键切换到最优健康节点。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                Button {
                    switching = true
                    Task {
                        await state.failoverToBestNode()
                        switching = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if switching { ProgressView().controlSize(.small).tint(.red) }
                        Text("切换到最优节点").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.red)
                .disabled(switching)
                .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
    }
}
