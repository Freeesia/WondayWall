import CoreGraphics
import EventKit
import Foundation

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

    // 保存済み予定をもとに EventKit から現在の詳細情報を取得する
    func fetchEventDetail(for savedEvent: CalendarEventItem) -> CalendarEventDetail? {
        guard authorizationStatus() == .fullAccess else { return nil }

        if let event = eventStore.event(withIdentifier: savedEvent.id) {
            return makeDetail(from: event, savedEvent: savedEvent)
        }

        guard let event = findMatchingEvent(for: savedEvent) else { return nil }
        return makeDetail(from: event, savedEvent: savedEvent)
    }

    private func findMatchingEvent(for savedEvent: CalendarEventItem) -> EKEvent? {
        let queryStart = savedEvent.startTime.addingTimeInterval(-12 * 60 * 60)
        let queryEndBase = savedEvent.endTime ?? savedEvent.startTime
        let queryEnd = queryEndBase.addingTimeInterval(12 * 60 * 60)
        let matchingCalendars = fetchCalendars()
            .filter { $0.calendarIdentifier == savedEvent.calendarId }

        if let match = searchMatchingEvent(
            savedEvent,
            from: queryStart,
            to: queryEnd,
            calendars: matchingCalendars.isEmpty ? nil : matchingCalendars
        ) {
            return match
        }

        return searchMatchingEvent(savedEvent, from: queryStart, to: queryEnd, calendars: nil)
    }

    private func searchMatchingEvent(
        _ savedEvent: CalendarEventItem,
        from start: Date,
        to end: Date,
        calendars: [EKCalendar]?
    ) -> EKEvent? {
        fetchEvents(from: start, to: end, calendars: calendars)
            .first { event in
                normalized(event.title) == normalized(savedEvent.title)
                    && abs(event.startDate.timeIntervalSince(savedEvent.startTime)) < 60
            }
    }

    private func makeDetail(from event: EKEvent, savedEvent: CalendarEventItem) -> CalendarEventDetail {
        CalendarEventDetail(
            id: event.eventIdentifier ?? savedEvent.id,
            title: nonEmpty(event.title) ?? savedEvent.title,
            startTime: event.startDate,
            endTime: event.endDate,
            isAllDay: event.isAllDay,
            location: nonEmpty(event.location),
            notes: nonEmpty(event.notes),
            calendarTitle: nonEmpty(event.calendar.title),
            calendarColorHex: colorHex(event.calendar.cgColor),
            urlString: nonEmpty(event.url?.absoluteString),
            organizerName: participantName(event.organizer),
            attendeeNames: attendeeNames(event.attendees),
            isLiveEventKitData: true
        )
    }

    private func attendeeNames(_ attendees: [EKParticipant]?) -> [String] {
        var seen: Set<String> = []
        return (attendees ?? []).compactMap { participant in
            guard let name = participantName(participant), !seen.contains(name) else { return nil }
            seen.insert(name)
            return name
        }
    }

    private func participantName(_ participant: EKParticipant?) -> String? {
        guard let participant else { return nil }
        return nonEmpty(participant.name)
            ?? nonEmpty(participant.url.absoluteString)
    }

    private func normalized(_ value: String?) -> String {
        nonEmpty(value) ?? ""
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    // CGColor を "#RRGGBB" 16進数文字列に変換する
    private func colorHex(_ cgColor: CGColor?) -> String? {
        guard let components = cgColor?.components else { return nil }
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat

        if components.count >= 3 {
            red = components[0]
            green = components[1]
            blue = components[2]
        } else if let white = components.first {
            red = white
            green = white
            blue = white
        } else {
            return nil
        }

        return String(
            format: "#%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255)
        )
    }
}
