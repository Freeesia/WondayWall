import EventKit

// EventKit を使って標準カレンダーへアクセスするサービス
// Google / iCloud / Exchange / CalDAV / 購読カレンダーをまとめて扱う
final class EventKitCalendarService {
    private let eventStore = EKEventStore()

    // カレンダーへのフルアクセス権限をリクエストする
    func requestAccess() async throws -> Bool {
        return try await eventStore.requestFullAccessToEvents()
    }

    // 現在の権限ステータスを返す
    func authorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    // 端末に登録されているカレンダー一覧を返す
    func fetchCalendars() -> [EKCalendar] {
        eventStore.calendars(for: .event)
    }

    // 端末の既定カレンダー識別子を返す
    func defaultCalendarIdentifierForNewEvents() -> String? {
        eventStore.defaultCalendarForNewEvents?.calendarIdentifier
    }

    // 指定カレンダーの今後 7 日間のイベントを取得する
    func fetchEvents(
        from start: Date = Date(),
        to end: Date = Date().addingTimeInterval(7 * 24 * 3600),
        calendars: [EKCalendar]? = nil
    ) -> [EKEvent] {
        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: calendars
        )
        return eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
    }
}
