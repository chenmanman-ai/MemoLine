import SwiftUI
import MemoCore

struct HangingMemoView: View {
    let memo: Memo
    @ObservedObject var store: MemoStore
    @ObservedObject var state: LineState
    var edit: () -> Void
    var reorder: (CGFloat) -> Void
    var complete: () -> Void
    var discard: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    @State private var arrived = false
    @State private var swing = 0.0
    @State private var dragX: CGFloat = 0
    @State private var ringOffset: CGFloat = 0
    @State private var showingPriority = false
    private var tilt: Double { Double(memo.id.uuid.0 % 9) / 2 - 2 }
    private var reminderIsNear: Bool {
        guard [.scheduled, .snoozed].contains(memo.reminderState),
              let date = memo.effectiveReminderDate else { return false }
        return date.timeIntervalSinceNow > 0 && date.timeIntervalSinceNow <= 60 * 60
    }

    var body: some View {
        VStack(spacing: -12) {
            Clothespin().zIndex(1)
            card
                .opacity(state.editingID == memo.id ? 0 : 1)
        }
        .frame(width: LineLayout.cardWidth, height: 278, alignment: .top)
        .rotationEffect(.degrees(tilt + (reduceMotion ? 0 : swing)), anchor: .top)
        .offset(x: dragX + ringOffset, y: arrived || reduceMotion || state.previewOnly ? 0 : -42)
        .opacity(arrived || reduceMotion || state.previewOnly ? 1 : 0)
        .onChange(of: showingPriority) { _, showing in state.showingMenu = showing }
        .onDisappear { if showingPriority { state.showingMenu = false } }
        .onAppear {
            if reduceMotion { arrived = true }
            else {
                swing = 5
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { arrived = true; swing = 0 }
            }
        }
        .task(id: reduceMotion) {
            guard !reduceMotion else { swing = 0; return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(Double.random(in: 15...26))) } catch { return }
                guard state.revealed, !hovered, !state.dragging else { continue }
                withAnimation(.easeInOut(duration: 0.6)) { swing = 0.65 }
                do { try await Task.sleep(for: .seconds(0.6)) } catch { return }
                withAnimation(.spring(response: 1.3, dampingFraction: 0.65)) { swing = 0 }
            }
        }
        .task(id: "\(memo.reminderState.rawValue)-\(reduceMotion)") {
            guard memo.reminderState == .ringing, !reduceMotion else {
                ringOffset = 0
                return
            }
            var direction: CGFloat = 1
            while !Task.isCancelled && memo.reminderState == .ringing {
                withAnimation(.easeInOut(duration: 0.11)) { ringOffset = 2.5 * direction }
                direction *= -1
                do { try await Task.sleep(for: .milliseconds(115)) } catch { return }
            }
            ringOffset = 0
        }
    }
    private var card: some View {
        interactiveCard
            .contextMenu { MemoActions(memo: memo, store: store, edit: edit, complete: complete, discard: discard) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityDescription)
            .accessibilityAction(named: "停止提醒") {
                if memo.reminderState == .ringing { store.acknowledgeReminder(memo.id) }
            }
            .accessibilityAction(named: "编辑", edit)
            .background(GeometryReader { geo in
                Color.clear.preference(key: HitRectsKey.self, value: [memo.id: geo.frame(in: .named("line"))])
            })
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader
            if memo.type == .todo {
                checklist
            } else {
                Text(memo.text)
                    .font(.system(size: 15)).lineSpacing(3).lineLimit(6)
                    .strikethrough(memo.status == .completed)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if let reminder = ReminderDates.label(for: memo) {
                Text(reminder).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(red: 0.72, green: 0.28, blue: 0.02))
            }
            if memo.reminderState == .acknowledged { acknowledgedActions }
            cardFooter
        }
    }

    private var styledCard: some View {
        cardContent
        .padding(14).padding(.top, 5)
        .frame(width: LineLayout.cardWidth, height: 258)
        .foregroundStyle(Color(white: 0.16))
        .background(PaperSurface(seed: Int(memo.id.uuid.0)))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 2).fill(memo.priority.blue)
                .frame(height: 3).padding(.horizontal, 10)
        }
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.brown.opacity(0.12), lineWidth: 0.6))
        .overlay(reminderBorder)
        .saturation(memo.status == .completed ? 0.4 : 1)
        .shadow(color: .black.opacity(scheme == .dark ? 0.24 : 0.13), radius: hovered ? 12 : 8, y: 5)
        .scaleEffect(!reduceMotion && hovered ? 1.025 : 1, anchor: .top)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovered)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovered = $0 }
    }

    private var interactiveCard: some View {
        styledCard
        .overlay {
            if memo.reminderState == .ringing {
                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.001))
                    .onTapGesture { store.acknowledgeReminder(memo.id) }
                    .accessibilityLabel("停止提醒")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .onTapGesture(count: 2) {
            if memo.reminderState == .ringing { store.acknowledgeReminder(memo.id) }
            else { edit() }
        }
        .onTapGesture {
            if memo.reminderState == .ringing { store.acknowledgeReminder(memo.id) }
            else { state.selected = memo.id }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 8)
            .onChanged { value in state.dragging = true; dragX = value.translation.width }
            .onEnded { value in reorder(value.translation.width); dragX = 0; state.dragging = false })
    }

    private var reminderBorder: some View {
        let color: Color = memo.reminderState == .ringing ? .red
            : (reminderIsNear ? .orange : (state.selected == memo.id ? .accentColor : .clear))
        let width: CGFloat = memo.reminderState == .ringing ? 3 : 2
        return RoundedRectangle(cornerRadius: 12).strokeBorder(color, lineWidth: width)
    }

    private var accessibilityDescription: String {
        (memo.type == .todo ? "待办便签" : "文本便签")
            + (memo.reminderState == .ringing ? "，提醒正在响铃" : "")
    }

    private var cardHeader: some View {
        HStack(spacing: 7) {
            Button { showingPriority = true } label: {
                PriorityBadge(priority: memo.priority)
            }
                .buttonStyle(.plain)
                .popover(isPresented: $showingPriority, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("优先级").font(.headline)
                        ForEach(MemoPriority.allCases, id: \.self) { priority in
                            Button {
                                store.setPriority(memo.id, priority)
                                showingPriority = false
                            } label: {
                                HStack {
                                    PriorityBadge(priority: priority)
                                    Spacer()
                                    if memo.priority == priority { Image(systemName: "checkmark") }
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.padding(14).frame(width: 150)
                }
                .accessibilityLabel("修改优先级，当前 \(memo.priority.title)")
                .help("修改优先级")
            Spacer()
            if memo.isPinned {
                Image(systemName: "pin.fill").font(.system(size: 12))
                    .foregroundStyle(Color.gray).rotationEffect(.degrees(20)).accessibilityLabel("已置顶")
            }
        }
    }

    private var checklist: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(memo.todoItems) { item in
                    HStack(alignment: .top, spacing: 7) {
                        Button {
                            if !item.isChecked && memo.todoItems.filter({ !$0.isChecked }).count == 1 {
                                complete()
                            } else { store.toggleTodoItem(memo.id, itemID: item.id) }
                        } label: {
                            Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(item.isChecked ? Color.gray : Color(red: 0.23, green: 0.40, blue: 0.60))
                        }
                        .buttonStyle(.plain).disabled(memo.status != .active)
                        .accessibilityLabel("\(item.isChecked ? "取消完成" : "完成")：\(item.text)")
                        Text(item.text).font(.system(size: 14)).strikethrough(item.isChecked)
                            .foregroundStyle(Color(white: item.isChecked ? 0.44 : 0.16))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var acknowledgedActions: some View {
        HStack(spacing: 8) {
            Button("完成", action: complete).buttonStyle(.borderless)
            Menu("稍后提醒") {
                Button("10 分钟后") { store.snoozeReminder(memo.id, until: ReminderDates.snooze(10)) }
                Button("30 分钟后") { store.snoozeReminder(memo.id, until: ReminderDates.snooze(30)) }
                Button("1 小时后") { store.snoozeReminder(memo.id, until: ReminderDates.snooze(60)) }
                Button("明天") { store.snoozeReminder(memo.id, until: ReminderDates.tomorrow()) }
            }
            .menuStyle(.borderlessButton)
        }
        .font(.system(size: 10, weight: .semibold))
    }

    private var cardFooter: some View {
        HStack(spacing: 10) {
            if memo.type == .todo {
                Text("\(memo.todoItems.filter(\.isChecked).count)/\(memo.todoItems.count)")
                    .font(.system(size: 10)).foregroundStyle(Color.gray)
            }
            Spacer()
            Button { ReminderPrompt.present(for: memo, store: store) } label: {
                Image(systemName: memo.reminderState == .none ? "alarm" : "alarm.fill")
                    .foregroundStyle(Color(red: 0.72, green: 0.28, blue: 0.02))
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("设置或修改提醒")
            .disabled(memo.status != .active).help("设置或修改提醒")
            Divider().frame(height: 12)
            Button(action: discard) { Image(systemName: "trash").frame(width: 24, height: 24) }
                .buttonStyle(.plain).help("删除便签，可撤销").accessibilityLabel("删除便签")
            Divider().frame(height: 12)
            Button(action: edit) { Image(systemName: "pencil").frame(width: 24, height: 24) }
                .buttonStyle(.plain).help("编辑便签").accessibilityLabel("编辑便签")
        }
        .font(.system(size: 13)).foregroundStyle(Color(white: 0.42))
    }
}
