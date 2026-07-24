import SwiftUI

/// A step-by-step in-app guide, opened from the Help menu.
struct TutorialView: View {
    private struct Step: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let body: String
    }

    private var steps: [Step] {
        [
            Step(icon: "cable.connector", title: L("tut.connect.t"), body: L("tut.connect.b")),
            Step(icon: "doc.on.doc", title: L("tut.load.t"), body: L("tut.load.b")),
            Step(icon: "slider.horizontal.3", title: L("tut.options.t"), body: L("tut.options.b")),
            Step(icon: "doc.text.magnifyingglass", title: L("tut.format.t"), body: L("tut.format.b")),
            Step(icon: "wand.and.stars", title: L("tut.extras.t"), body: L("tut.extras.b")),
            Step(icon: "arrow.up.arrow.down", title: L("tut.arrange.t"), body: L("tut.arrange.b")),
            Step(icon: "folder", title: L("tut.save.t"), body: L("tut.save.b")),
            Step(icon: "gearshape", title: L("tut.defaults.t"), body: L("tut.defaults.b")),
            Step(icon: "exclamationmark.triangle", title: L("tut.trouble.t"), body: L("tut.trouble.b")),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("tutorial.title")).font(.largeTitle).bold()
                    Text(L("tutorial.intro"))
                        .font(.title3).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle().fill(Color.accentColor.opacity(0.15))
                            Image(systemName: step.icon)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.accentColor)
                        }
                        .frame(width: 42, height: 42)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(index + 1). \(step.title)").font(.headline)
                            Text(step.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 520, minHeight: 480)
    }
}
