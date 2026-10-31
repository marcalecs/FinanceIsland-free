import SwiftUI

@MainActor
struct TradingSettings: View {
    static let examples = ["e.g. The trend on the hour chart agrees", "e.g. The stop is set before I enter", "e.g. Risk is 1R or less",
                           "e.g. No news in the next 30 minutes", "e.g. I'm calm, not chasing a loss"]

    @ObservedObject var settings: AppSettings
    @ObservedObject private var prefs = TradePrefs.shared
    @ObservedObject private var license = LicenseStore.shared
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Paper trading and risk") {
                Row(title: "Taker fee, %", subtitle: "Charged on entry and on exit; volume is sized so the loss at the stop with both fees equals the risk") {
                    number($prefs.v.feePercent)
                }
                Row(title: "Breakeven buffer, %", subtitle: "Breakeven = entry ± (2 × fee + buffer)", divider: false) {
                    number($prefs.v.bufferPercent)
                }
            }
            SettingsSection(title: "Tilt Guard") {
                if license.isActive {
                    Row(title: "Daily loss limit", subtitle: prefs.v.tilt.dailyLoss > 0 ? nil : "Off") {
                        HStack(spacing: 6) {
                            number($prefs.v.tilt.dailyLoss, allowZero: true)
                            PillPicker(options: [false, true], selection: $prefs.v.tilt.dailyLossInR,
                                       label: { $0 ? "R" : settings.baseCurrency }, minWidth: 34)
                        }
                    }
                    Row(title: "Max trades a day", subtitle: prefs.v.tilt.maxTrades > 0 ? nil : "Off") { stepper($prefs.v.tilt.maxTrades, 0...50) }
                    Row(title: "Max losing trades in a row", subtitle: prefs.v.tilt.maxLossStreak > 0 ? nil : "Off") { stepper($prefs.v.tilt.maxLossStreak, 0...20) }
                    Row(title: "Pause after a stop, minutes", subtitle: prefs.v.tilt.pauseMinutes > 0 ? nil : "Off") { stepper($prefs.v.tilt.pauseMinutes, 0...240, step: 5) }
                    Row(title: "Reminder when you open", subtitle: "During a pause or after the daily limit, opening one of these apps shows a calm reminder in the island. Nothing is closed or blocked. Websites in a browser aren't tracked. Bundle id or app name, comma separated.") {
                        TextField("", text: Binding(get: { prefs.v.watchApps.joined(separator: ", ") },
                                                    set: { prefs.v.watchApps = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                            .textFieldStyle(.plain).font(.system(size: 12.5))
                            .padding(.horizontal, 10).frame(width: 260, height: 28)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(look.theme.chip))
                    }
                    Row(title: "The day starts at midnight in", subtitle: "Counts manual and paper trades, never simulated ones. Only new entries are blocked.", divider: false) {
                        Picker("", selection: $prefs.v.tilt.timeZone) {
                            Text(tr("This Mac's time zone")).tag("")
                            ForEach(["UTC", "Europe/London", "Europe/Berlin", "Europe/Moscow", "Asia/Dubai", "Asia/Shanghai", "Asia/Tokyo",
                                     "America/New_York", "America/Chicago", "America/Los_Angeles"], id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden().pickerStyle(.menu).frame(width: 190)
                    }
                } else {
                    ProPreview(feature: .tiltGuard).padding(.vertical, 8)
                }
            }
            SettingsSection(title: "Pre-trade checklist") {
                Row(title: "Your rules before an entry", subtitle: "3–5 short items, shown as ticks before a manual or paper trade. You can always enter without every tick; the trade remembers how many you ticked.") {
                    EmptyView()
                }
                ForEach(0..<5, id: \.self) { i in
                    TextField(tr(Self.examples[i]), text: Binding(
                        get: { i < prefs.v.checklist.count ? prefs.v.checklist[i] : "" },
                        set: { v in
                            var l = prefs.v.checklist
                            while l.count <= i { l.append("") }
                            l[i] = v
                            while let last = l.last, last.trimmingCharacters(in: .whitespaces).isEmpty { l.removeLast() }
                            prefs.v.checklist = l
                        }))
                        .textFieldStyle(.plain).font(.system(size: 12.5))
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(look.theme.chip))
                        .padding(.vertical, 3)
                }
                Row(title: "Also before paper trades", subtitle: "Off: paper hotkeys enter at once", divider: false) {
                    Switch(isOn: $prefs.v.checklistForPaper)
                }
            }
            SettingsSection(title: "Trade tags") {
                Row(title: "Setups", subtitle: "Comma separated") { tags($prefs.v.setupTags) }
                Row(title: "Mistakes", subtitle: "Comma separated", divider: false) { tags($prefs.v.mistakeTags) }
            }
            SettingsSection(title: "Hotkeys") {
                ForEach(Array([("long", "Long"), ("short", "Short"), ("breakeven", "Breakeven"), ("close", "Close")].enumerated()), id: \.offset) { i, k in
                    Row(title: k.1, subtitle: i == 3 ? "Work only while the island has focus and no text field is active" : nil, divider: i < 3) {
                        TextField("", text: Binding(get: { prefs.v.keys[k.0] ?? "" },
                                                    set: { prefs.v.keys[k.0] = String($0.lowercased().suffix(1)) }))
                            .textFieldStyle(.plain).font(.system(size: 13).monospacedDigit())
                            .multilineTextAlignment(.center)
                            .frame(width: 40, height: 28)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(look.theme.chip))
                    }
                }
            }
        }
    }

    private func number(_ v: Binding<Double>, allowZero: Bool = false) -> some View {
        TextField(tr("off"), text: Binding(
            get: { v.wrappedValue > 0 ? String(format: "%g", v.wrappedValue) : "" },
            set: {
                let x = Double($0.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) ?? 0
                if x >= 0, allowZero || x > 0 { v.wrappedValue = x }
            }))
            .textFieldStyle(.plain).font(.system(size: 13).monospacedDigit())
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 10).frame(width: 90, height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(look.theme.chip))
    }

    private func stepper(_ v: Binding<Int>, _ range: ClosedRange<Int>, step: Int = 1) -> some View {
        Stepper(value: v, in: range, step: step) {
            Text(v.wrappedValue == 0 ? tr("off") : "\(v.wrappedValue)").font(.system(size: 13).monospacedDigit()).frame(minWidth: 30)
        }
        .fixedSize()
    }

    private func tags(_ v: Binding<[String]>) -> some View {
        TextField("", text: Binding(
            get: { v.wrappedValue.joined(separator: ", ") },
            set: { s in
                v.wrappedValue = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    .map { $0.hasPrefix("#") ? $0 : "#" + $0 }
            }))
            .textFieldStyle(.plain).font(.system(size: 12.5))
            .padding(.horizontal, 10).frame(width: 300, height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(look.theme.chip))
    }
}
