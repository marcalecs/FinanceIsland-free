import SwiftUI

struct AlertsCard: View {
    let subject: HubSubject
    let price: Double?
    @ObservedObject private var store = AlertStore.shared
    @ObservedObject private var license = LicenseStore.shared
    @Environment(\.look) private var look
    @State private var kind: PriceAlert.Kind = .above
    @State private var value = ""
    @State private var hours = 24.0

    private func fmt(_ v: Double) -> String { subject.format(v) }

    var body: some View {
        let mine = store.alerts(for: subject.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("Price alerts")).font(.system(size: 14, weight: .bold))
                Spacer()
                if !license.isActive {
                    Text(tr("\(store.activeCount) of \(ProFeature.freePriceAlerts) free"))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
            }
            ForEach(mine) { a in
                HStack(spacing: 10) {
                    Image(systemName: a.active ? "bell.fill" : "bell.slash").font(.system(size: 12))
                        .foregroundStyle(a.active ? look.accent : .white.opacity(0.4))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(AlertStore.describe(a, format: fmt)).font(.system(size: 12.5, weight: .semibold))
                        if let t = a.firedAt {
                            Text(tr("Fired \(Fmt.date(t, "d MMM HH:mm")) at \(a.firedPrice.map(fmt) ?? "—")"))
                                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    Spacer()
                    if !a.active {
                        Button(tr("Turn on again")) { store.rearm(a.id) }
                            .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(look.accent)
                            .disabled(!store.canAdd)
                    }
                    Button { store.remove(a.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.55))
                            .frame(width: 22, height: 22).background(Circle().fill(look.theme.chip))
                    }
                    .buttonStyle(.plain)
                    .help(tr("Delete the alert"))
                }
            }
            if store.canAdd {
                HStack(spacing: 8) {
                    Picker("", selection: $kind) {
                        Text(tr("Price above")).tag(PriceAlert.Kind.above)
                        Text(tr("Price below")).tag(PriceAlert.Kind.below)
                        Text(tr("Rises by %")).tag(PriceAlert.Kind.risesBy)
                        Text(tr("Falls by %")).tag(PriceAlert.Kind.fallsBy)
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 130)
                    TextField(placeholder, text: $value)
                        .textFieldStyle(.plain).font(.system(size: 13).monospacedDigit())
                        .padding(.horizontal, 10).frame(width: 110, height: 28)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(look.theme.chip))
                        .onSubmit(add)
                    if kind == .risesBy || kind == .fallsBy {
                        PillPicker(options: [1.0, 4, 24, 168], selection: $hours, label: { $0 == 168 ? tr("1w") : tr("\(Int($0))h") }, minWidth: 30)
                    }
                    Spacer()
                    Button(tr("Add alert"), action: add)
                        .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(Capsule().fill(look.theme.chip))
                        .disabled(number == nil)
                }
            } else {
                ProPreview(feature: .unlimitedAlerts)
            }
            Text(tr("Checked every minute on this Mac, even with the island closed. A fired alert switches itself off."))
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
        .onChange(of: kind) { _, _ in value = "" }
    }

    private var placeholder: String {
        switch kind {
        case .above: return price.map { fmt($0 * 1.02) } ?? tr("price")
        case .below: return price.map { fmt($0 * 0.98) } ?? tr("price")
        case .risesBy, .fallsBy: return "5 %"
        }
    }

    private var number: Double? {
        Double(value.replacingOccurrences(of: ",", with: ".").filter { "0123456789.".contains($0) }).flatMap { $0 > 0 ? $0 : nil }
    }

    private func add() {
        guard let v = number else { return }
        if store.add(PriceAlert(subject: subject.id, name: subject.short, kind: kind, value: v, hours: hours)) { value = "" }
    }
}
