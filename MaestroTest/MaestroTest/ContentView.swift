//
//  ContentView.swift
//  MaestroTest
//

import SwiftUI
import SwiftData

@Model
final class Counter {
    var value: Int
    init(value: Int = 0) { self.value = value }
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query private var counters: [Counter]

    var body: some View {
        let counter = counters.first
        VStack(spacing: 24) {
            Text("\(counter?.value ?? 0)")
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .accessibilityIdentifier("counterValue")

            Button("Increment") {
                if let counter {
                    counter.value += 1
                } else {
                    context.insert(Counter(value: 1))
                }
                try? context.save()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("incrementButton")
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Counter.self, inMemory: true)
}
