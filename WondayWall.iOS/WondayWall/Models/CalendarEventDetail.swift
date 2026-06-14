import Foundation

// 予定詳細シートで表示する一時データ
struct CalendarEventDetail: Identifiable {
    let id: String
    let title: String
    let startTime: Date
    let endTime: Date?
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let calendarTitle: String?
    let calendarColorHex: String?
    let urlString: String?
    let organizerName: String?
    let attendeeNames: [String]
    let isLiveEventKitData: Bool

    init(
        id: String,
        title: String,
        startTime: Date,
        endTime: Date?,
        isAllDay: Bool,
        location: String?,
        notes: String?,
        calendarTitle: String?,
        calendarColorHex: String?,
        urlString: String?,
        organizerName: String?,
        attendeeNames: [String],
        isLiveEventKitData: Bool
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.calendarTitle = calendarTitle
        self.calendarColorHex = calendarColorHex
        self.urlString = urlString
        self.organizerName = organizerName
        self.attendeeNames = attendeeNames
        self.isLiveEventKitData = isLiveEventKitData
    }

    init(savedEvent: CalendarEventItem) {
        self.init(
            id: savedEvent.id,
            title: savedEvent.title,
            startTime: savedEvent.startTime,
            endTime: savedEvent.endTime,
            isAllDay: savedEvent.isAllDay,
            location: savedEvent.location,
            notes: savedEvent.notes,
            calendarTitle: nil,
            calendarColorHex: nil,
            urlString: nil,
            organizerName: nil,
            attendeeNames: [],
            isLiveEventKitData: false
        )
    }
}
