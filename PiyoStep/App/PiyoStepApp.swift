import SwiftUI
import UIKit
import PiyoCore

@main
struct PiyoStepApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var environment: AppEnvironment

    init() {
        let created = AppEnvironmentFactory.makeLive()
        created.bootstrap()
        _environment = State(initialValue: created)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .task {
                    await environment.loadPurchases()
                }
                .onAppear(perform: keepScreenAwake)
        }
        .onChange(of: scenePhase) { _, _ in
            keepScreenAwake()
        }
    }

    /// アプリを使っている間は画面を消さない。
    ///
    /// 消灯してロックがかかると、自分では解除できない子がいる。
    /// 学習中もごはんタイマー中も、しばらく画面に触らない時間があるので、
    /// 画面ごとではなくアプリ全体でスリープを止める。
    private func keepScreenAwake() {
        UIApplication.shared.isIdleTimerDisabled = scenePhase == .active
    }
}
