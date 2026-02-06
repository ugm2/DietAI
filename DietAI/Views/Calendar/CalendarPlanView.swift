import SwiftUI
import SwiftData

// MARK: - Calendar View Mode
enum CalendarViewMode {
    case week
    case month
}

// MARK: - Calendar Plan View
struct CalendarPlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DietPlan.createdAt, order: .reverse) var plans: [DietPlan]

    @State private var selectedDate = Date()
    @State private var viewMode: CalendarViewMode = .week
    @State private var selectedPlan: DietPlan?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // View mode picker
                Picker("View", selection: $viewMode) {
                    Text("Week").tag(CalendarViewMode.week)
                    Text("Month").tag(CalendarViewMode.month)
                }
                .pickerStyle(.segmented)
                .padding()

                // Calendar
                if viewMode == .week {
                    WeekCalendarView(
                        selectedDate: $selectedDate,
                        plans: plans
                    )
                } else {
                    MonthCalendarView(
                        selectedDate: $selectedDate,
                        plans: plans
                    )
                }

                Divider()

                // Selected day meals
                DayMealsView(
                    date: selectedDate,
                    plan: findPlanForDate(selectedDate)
                )
            }
            .navigationTitle("Meal Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Today") {
                        withAnimation {
                            selectedDate = Date()
                        }
                    }
                }
            }
        }
    }

    private func findPlanForDate(_ date: Date) -> DietPlan? {
        // Get the day name for the selected date
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE"
        let dayName = formatter.string(from: date).lowercased()

        // Find a plan that has meals for this day of the week
        // First try to find a plan that explicitly covers this day
        if let planWithDay = plans.first(where: { plan in
            plan.days.contains { $0.dayName.lowercased() == dayName && !$0.meals.isEmpty }
        }) {
            return planWithDay
        }

        // Otherwise return the most recent plan
        return plans.first
    }
}

// MARK: - Week Calendar View
struct WeekCalendarView: View {
    @Binding var selectedDate: Date
    let plans: [DietPlan]

    private let calendar = Calendar.current
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    var weekDates: [Date] {
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate))!
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Week navigation
            HStack {
                Button(action: previousWeek) {
                    Image(systemName: "chevron.left")
                }

                Spacer()

                Text(weekRangeText)
                    .font(.headline)

                Spacer()

                Button(action: nextWeek) {
                    Image(systemName: "chevron.right")
                }
            }
            .padding(.horizontal)

            // Day cells
            HStack(spacing: 4) {
                ForEach(weekDates, id: \.self) { date in
                    DayCell(
                        date: date,
                        isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                        isToday: calendar.isDateInToday(date),
                        hasMeals: hasMeals(for: date)
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) {
                            selectedDate = date
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.vertical)
    }

    private var weekRangeText: String {
        let start = weekDates.first!
        let end = weekDates.last!
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private func previousWeek() {
        selectedDate = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedDate)!
    }

    private func nextWeek() {
        selectedDate = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedDate)!
    }

    private func hasMeals(for date: Date) -> Bool {
        // Check if any plan has meals for this day (case-insensitive)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE"
        let dayName = formatter.string(from: date).lowercased()

        return plans.contains { plan in
            plan.days.contains { $0.dayName.lowercased() == dayName && !$0.meals.isEmpty }
        }
    }
}

// MARK: - Day Cell
struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasMeals: Bool

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 4) {
            Text(dayOfWeek)
                .font(.caption2)
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 36, height: 36)

                Text("\(calendar.component(.day, from: date))")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(isSelected || isToday ? .bold : .regular)
                    .foregroundStyle(textColor)
            }

            // Meal indicator
            Circle()
                .fill(hasMeals ? Color.green : Color.clear)
                .frame(width: 6, height: 6)
        }
        .frame(maxWidth: .infinity)
    }

    private var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private var backgroundColor: Color {
        if isSelected { return .blue }
        if isToday { return .blue.opacity(0.2) }
        return .clear
    }

    private var textColor: Color {
        if isSelected { return .white }
        if isToday { return .blue }
        return .primary
    }
}

// MARK: - Month Calendar View
struct MonthCalendarView: View {
    @Binding var selectedDate: Date
    let plans: [DietPlan]

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            // Month navigation
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                }

                Spacer()

                Text(monthYearText)
                    .font(.headline)

                Spacer()

                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                }
            }
            .padding(.horizontal)

            // Weekday headers
            HStack {
                ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Days grid
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(monthDates, id: \.self) { date in
                    if let date = date {
                        MonthDayCell(
                            date: date,
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date),
                            isCurrentMonth: calendar.isDate(date, equalTo: selectedDate, toGranularity: .month)
                        )
                        .onTapGesture {
                            selectedDate = date
                        }
                    } else {
                        Color.clear
                            .frame(height: 36)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }

    private var monthYearText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedDate)
    }

    private var monthDates: [Date?] {
        let components = calendar.dateComponents([.year, .month], from: selectedDate)
        let firstOfMonth = calendar.date(from: components)!
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let daysInMonth = calendar.range(of: .day, in: .month, for: selectedDate)!.count

        var dates: [Date?] = Array(repeating: nil, count: firstWeekday - 1)

        for day in 1...daysInMonth {
            if let date = calendar.date(bySetting: .day, value: day, of: firstOfMonth) {
                dates.append(date)
            }
        }

        return dates
    }

    private func previousMonth() {
        selectedDate = calendar.date(byAdding: .month, value: -1, to: selectedDate)!
    }

    private func nextMonth() {
        selectedDate = calendar.date(byAdding: .month, value: 1, to: selectedDate)!
    }
}

struct MonthDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isCurrentMonth: Bool

    private let calendar = Calendar.current

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: 32, height: 32)

            Text("\(calendar.component(.day, from: date))")
                .font(.caption)
                .fontWeight(isSelected || isToday ? .bold : .regular)
                .foregroundStyle(textColor)
        }
    }

    private var backgroundColor: Color {
        if isSelected { return .blue }
        if isToday { return .blue.opacity(0.2) }
        return .clear
    }

    private var textColor: Color {
        if isSelected { return .white }
        if !isCurrentMonth { return .secondary.opacity(0.5) }
        if isToday { return .blue }
        return .primary
    }
}

// MARK: - Day Meals View
struct DayMealsView: View {
    let date: Date
    let plan: DietPlan?

    private var dayName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private var meals: [Meal] {
        guard let plan = plan else { return [] }
        // Case-insensitive comparison for day name
        return plan.days.first { $0.dayName.lowercased() == dayName.lowercased() }?.meals ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(date.formatted(date: .complete, time: .omitted))
                    .font(.headline)
                Spacer()
                if !meals.isEmpty {
                    Text("\(totalCalories) kcal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top)

            if meals.isEmpty {
                ContentUnavailableView(
                    "No meals planned",
                    systemImage: "calendar.badge.plus",
                    description: Text("Generate a plan to see meals for this day")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(meals) { meal in
                            CompactMealCard(meal: meal)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var totalCalories: Int {
        meals.reduce(0) { $0 + $1.calories }
    }
}

// MARK: - Compact Meal Card
struct CompactMealCard: View {
    let meal: Meal

    var body: some View {
        HStack(spacing: 12) {
            // Meal type icon
            Image(systemName: iconFor(meal.type))
                .font(.title3)
                .foregroundStyle(colorFor(meal.type))
                .frame(width: 40, height: 40)
                .background(colorFor(meal.type).opacity(0.15))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(meal.typeRaw)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(meal.calories)")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("kcal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func iconFor(_ type: MealType) -> String {
        type.icon
    }

    private func colorFor(_ type: MealType) -> Color {
        type.color
    }
}
