import ActivityKit
import WidgetKit
import SwiftUI

@main
struct StreamActivityBundle: WidgetBundle {
    var body: some Widget { StreamActivityWidget() }
}

struct StreamActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StreamActivityAttributes.self) { context in
            HStack {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text("Streaming").font(.headline)
                Spacer()
                Text(context.state.startedAt, style: .timer).monospacedDigit()
            }.padding().activityBackgroundTint(.black).activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Live", systemImage: "record.circle.fill").foregroundStyle(.red)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startedAt, style: .timer).monospacedDigit()
                }
            } compactLeading: {
                Circle().fill(.red).frame(width: 8, height: 8)
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer).monospacedDigit().frame(width: 56)
            } minimal: {
                Circle().fill(.red).frame(width: 8, height: 8)
            }
        }
    }
}

