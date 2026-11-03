import Foundation

public enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case kg, lb
    public var id: String { rawValue }
    public var toKg: Double { self == .kg ? 1 : 0.45359237 }
}

/// One set row from a Strong CSV export.
public struct StrongRow: Hashable {
    public var workoutKey: String
    public var date: Date
    public var workoutName: String
    public var durationSeconds: Double
    public var exerciseName: String
    public var setOrder: String
    public var weight: Double
    public var reps: Int
    public var distanceKm: Double
    public var seconds: Double
}

public struct StrongParseResult {
    public var rows: [StrongRow]
    /// Unit found in the header ("Weight (kg)" / "Weight (lbs)"); nil for older exports.
    public var detectedUnit: WeightUnit?
    public var skippedRows: Int

    /// Exercise names by how often they appear (most first).
    public var exerciseNames: [String] {
        var counts: [String: Int] = [:]
        for row in rows { counts[row.exerciseName, default: 0] += 1 }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }

    public var workoutCount: Int { Set(rows.map(\.workoutKey)).count }
    public var firstDate: Date? { rows.map(\.date).min() }
    public var lastDate: Date? { rows.map(\.date).max() }
}

public struct StrongImportOutcome {
    public var workouts: [WorkoutLog]
    public var duplicatesSkipped: Int
    public var setCount: Int { workouts.reduce(0) { $0 + $1.totalSets } }
}

public enum StrongImportError: LocalizedError {
    case notStrongFile
    case noRows

    public var errorDescription: String? {
        switch self {
        case .notStrongFile: return "This doesn't look like a Strong export. In Strong: Settings → Export Strong Data, then pick that CSV."
        case .noRows: return "No sets found in this file."
        }
    }
}

/// Reads Strong's CSV export (both the newer `;` format with units in the header and the older `,` format).
public enum StrongImporter {
    public static let importedRoutineID = UUID(uuidString: "5A0E5A0E-0000-4000-8000-000000000001")!

    public static func parse(_ text: String) throws -> StrongParseResult {
        let cleaned = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        guard let firstLine = cleaned.split(whereSeparator: \.isNewline).first else { throw StrongImportError.noRows }
        let delimiter: Character = firstLine.filter { $0 == ";" }.count > firstLine.filter { $0 == "," }.count ? ";" : ","
        let table = csvRows(cleaned, delimiter: delimiter)
        guard let header = table.first else { throw StrongImportError.noRows }

        let lower = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func column(_ prefix: String) -> Int? { lower.firstIndex { $0.hasPrefix(prefix) } }
        guard let dateCol = column("date"),
              let exerciseCol = column("exercise name"),
              let weightCol = column("weight"),
              let repsCol = column("reps") else { throw StrongImportError.notStrongFile }
        let numberCol = column("workout #")
        let nameCol = column("workout name")
        let durationCol = column("duration")
        let setCol = column("set order")
        let distanceCol = column("distance")
        let secondsCol = column("seconds")

        var unit: WeightUnit?
        if lower[weightCol].contains("lb") { unit = .lb } else if lower[weightCol].contains("kg") { unit = .kg }
        let distanceInMeters = distanceCol.map { lower[$0].contains("meter") || lower[$0].contains("(m)") } ?? false
        let distanceInMiles = distanceCol.map { lower[$0].contains("mile") } ?? false
        let durationInSeconds = durationCol.map { lower[$0].contains("sec") } ?? false

        var rows: [StrongRow] = []
        var skipped = 0
        for fields in table.dropFirst() {
            func value(_ index: Int?) -> String {
                guard let index, index < fields.count else { return "" }
                return fields[index].trimmingCharacters(in: .whitespaces)
            }
            guard let date = parseDate(value(dateCol)), !value(exerciseCol).isEmpty else {
                if fields.contains(where: { !$0.isEmpty }) { skipped += 1 }
                continue
            }
            let order = value(setCol).uppercased()
            // Skip warm-ups ("W") and rest-timer rows; keep numbered, drop ("D") and failure ("F") sets.
            if !order.isEmpty, Int(order) == nil, order != "D", order != "F" {
                skipped += 1
                continue
            }
            var distance = number(value(distanceCol))
            if distanceInMeters { distance /= 1000 } else if distanceInMiles { distance *= 1.609344 }
            let durationText = value(durationCol)
            let duration = durationInSeconds ? number(durationText) : parseDuration(durationText)
            let name = value(nameCol).isEmpty ? "Imported workout" : value(nameCol)
            let key = value(numberCol).isEmpty ? "\(value(dateCol))|\(name)" : value(numberCol)

            rows.append(StrongRow(
                workoutKey: key,
                date: date,
                workoutName: name,
                durationSeconds: duration,
                exerciseName: value(exerciseCol),
                setOrder: order,
                weight: number(value(weightCol)),
                reps: Int(number(value(repsCol))),
                distanceKm: distance,
                seconds: number(value(secondsCol))
            ))
        }
        guard !rows.isEmpty else { throw StrongImportError.noRows }
        return StrongParseResult(rows: rows, detectedUnit: unit, skippedRows: skipped)
    }

    /// Builds workouts. `mapping` links a Strong exercise name to one of your exercises so history merges.
    public static func buildWorkouts(
        from parsed: StrongParseResult,
        unit: WeightUnit,
        mapping: [String: ExerciseDefinition],
        existing: [WorkoutLog]
    ) -> StrongImportOutcome {
        var order: [String] = []
        var grouped: [String: [StrongRow]] = [:]
        for row in parsed.rows {
            if grouped[row.workoutKey] == nil { order.append(row.workoutKey) }
            grouped[row.workoutKey, default: []].append(row)
        }

        var workouts: [WorkoutLog] = []
        var duplicates = 0
        var generatedIDs: [String: UUID] = [:]

        for key in order {
            guard let rows = grouped[key], let first = rows.first else { continue }
            let isDuplicate = existing.contains {
                abs($0.startedAt.timeIntervalSince(first.date)) < 120
                    && $0.routineName.lowercased() == first.workoutName.lowercased()
            }
            if isDuplicate {
                duplicates += 1
                continue
            }

            var exerciseOrder: [String] = []
            var byExercise: [String: [StrongRow]] = [:]
            for row in rows {
                if byExercise[row.exerciseName] == nil { exerciseOrder.append(row.exerciseName) }
                byExercise[row.exerciseName, default: []].append(row)
            }

            var exerciseLogs: [ExerciseLog] = []
            for name in exerciseOrder {
                let setRows = byExercise[name] ?? []
                let mapped = mapping[name]
                let category = mapped?.category ?? ExerciseCategory.guess(from: name)
                let sets: [WorkoutSetLog] = setRows.enumerated().map { index, row in
                    let isCardioRow = row.reps == 0 && (row.seconds > 0 || row.distanceKm > 0)
                    return WorkoutSetLog(
                        setNumber: index + 1,
                        weightKg: isCardioRow ? 0 : ((row.weight * unit.toKg) * 100).rounded() / 100,
                        reps: row.reps,
                        completedAt: first.date.addingTimeInterval(Double(index) * 150),
                        durationSeconds: isCardioRow ? row.seconds : nil,
                        distanceKm: isCardioRow && row.distanceKm > 0 ? row.distanceKm : nil
                    )
                }
                guard !sets.isEmpty else { continue }
                let id: UUID
                if let mapped {
                    id = mapped.id
                } else if let existingID = generatedIDs[name] {
                    id = existingID
                } else {
                    id = UUID()
                    generatedIDs[name] = id
                }
                exerciseLogs.append(ExerciseLog(
                    exerciseID: id,
                    exerciseName: mapped?.loggedName ?? name,
                    repMinAtTime: mapped?.repMin ?? 8,
                    repMaxAtTime: mapped?.repMax ?? 12,
                    weightIncrementKgAtTime: mapped?.weightIncrementKg ?? 2.5,
                    sets: sets,
                    category: sets.allSatisfy(\.isCardio) ? .cardio : category
                ))
            }
            guard !exerciseLogs.isEmpty else { continue }

            let setCount = exerciseLogs.reduce(0) { $0 + $1.sets.count }
            let duration = first.durationSeconds > 0 ? first.durationSeconds : Double(setCount) * 150
            workouts.append(WorkoutLog(
                routineID: importedRoutineID,
                routineName: first.workoutName,
                startedAt: first.date,
                endedAt: first.date.addingTimeInterval(duration),
                exercises: exerciseLogs,
                source: "strong"
            ))
        }
        return StrongImportOutcome(workouts: workouts, duplicatesSkipped: duplicates)
    }

    // MARK: Parsing helpers

    /// RFC 4180-style CSV: quoted fields, doubled quotes, newlines inside quotes.
    public static func csvRows(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()
        var pending: Character? = nil

        while true {
            let char: Character
            if let saved = pending {
                char = saved
                pending = nil
            } else if let next = iterator.next() {
                char = next
            } else {
                break
            }
            if inQuotes {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else if char == "\"" {
                inQuotes = true
            } else if char == delimiter {
                row.append(field)
                field = ""
            } else if char == "\n" || char == "\r" || char == "\r\n" {
                row.append(field)
                field = ""
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
            } else {
                field.append(char)
            }
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }

    static func number(_ text: String) -> Double {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return Double(cleaned) ?? 0
    }

    static func parseDate(_ text: String) -> Date? {
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd", "dd/MM/yyyy HH:mm", "MM/dd/yyyy HH:mm"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return ISO8601DateFormatter().date(from: text)
    }

    /// "1h 5m", "45m", "1h", "50s" or plain seconds → seconds.
    static func parseDuration(_ text: String) -> Double {
        let trimmed = text.lowercased().trimmingCharacters(in: .whitespaces)
        if let plain = Double(trimmed) { return plain }
        var total = 0.0
        var digits = ""
        for char in trimmed {
            if char.isNumber || char == "." {
                digits.append(char)
            } else if let value = Double(digits) {
                switch char {
                case "h": total += value * 3600
                case "m": total += value * 60
                case "s": total += value
                default: break
                }
                digits = ""
            }
        }
        return total
    }
}
