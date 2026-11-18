import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

// MARK: - 대시보드
struct GolfDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<RoundRecord> { $0.isArchived == false },
           sort: \RoundRecord.date, order: .reverse)
    private var records: [RoundRecord]
    @State private var showingInput = false

    var body: some View {
        NavigationStack {
            List {
                if records.isEmpty {
                    ContentUnavailableView("기록 없음", systemImage: "figure.golf",
                        description: Text("우측 상단 + 버튼으로 라운드를 추가하세요."))
                } else {
                    ForEach(records) { record in
                        NavigationLink(destination: RecordDetailView(record: record)) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(record.courseName).bold()
                                    Spacer()
                                    Text(record.date, style: .date)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                HStack {
                                    Text("\(record.totalScore)타").bold().foregroundStyle(.blue)
                                    Spacer()
                                    Text(record.dataSource.rawValue)
                                        .font(.caption2).padding(4)
                                        .background(Color.gray.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets {
                            records[i].isArchived = true
                            records[i].updatedAt = Date()
                        }
                    }
                }
            }
            .navigationTitle("MY GOLF")
            .toolbar {
                Button { showingInput = true } label: { Label("기록 추가", systemImage: "plus") }
            }
            .sheet(isPresented: $showingInput) { ManualInputView() }
        }
    }
}

// MARK: - 직접 입력
private struct HoleInput: Identifiable {
    let id = UUID()
    let number: Int
    var par = 4
    var strokes = 4
    var putts = 2
    var fairwayHit = false
    var gir = false
}

struct ManualInputView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var courseName = ""
    @State private var date = Date()
    @State private var courseRating = 72.0
    @State private var slopeRating = 113.0
    @State private var driverDistance = 0.0
    @State private var holes: [HoleInput] = (1...18).map { HoleInput(number: $0) }
    @State private var pickerItem: PhotosPickerItem?
    @State private var imageData: Data?

    private var totalScore: Int { holes.map(\.strokes).reduce(0, +) }
    private var totalPutts: Int { holes.map(\.putts).reduce(0, +) }
    private var fairwayHoles: [HoleInput] { holes.filter { $0.par > 3 } }
    private var fairwaysHit: Int { fairwayHoles.filter(\.fairwayHit).count }
    private var gir: Int { holes.filter(\.gir).count }

    var body: some View {
        NavigationStack {
            Form {
                Section("라운드 정보") {
                    TextField("골프장 이름", text: $courseName)
                    DatePicker("날짜", selection: $date, displayedComponents: .date)
                    HStack {
                        Text("코스 레이팅"); Spacer()
                        TextField("72.0", value: $courseRating, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                    }
                    HStack {
                        Text("슬로프"); Spacer()
                        TextField("113", value: $slopeRating, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                    }
                    HStack {
                        Text("평균 드라이버 비거리(m)"); Spacer()
                        TextField("선택", value: $driverDistance, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                    }
                }

                Section("스코어카드 사진") {
                    if let imageData, let img = UIImage(data: imageData) {
                        Image(uiImage: img).resizable().scaledToFit().frame(height: 180)
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(imageData == nil ? "사진 첨부" : "사진 변경", systemImage: "photo")
                    }
                }
                .onChange(of: pickerItem) { _, item in
                    Task {
                        guard let data = try? await item?.loadTransferable(type: Data.self),
                              let img = UIImage(data: data) else { return }
                        imageData = img.jpegData(compressionQuality: 0.7)
                    }
                }

                Section("요약") {
                    LabeledContent("총 타수", value: "\(totalScore)타")
                    LabeledContent("총 퍼팅", value: "\(totalPutts)개")
                    LabeledContent("페어웨이", value: "\(fairwaysHit)/\(fairwayHoles.count)")
                    LabeledContent("GIR", value: "\(gir)/18")
                }

                ForEach($holes) { $h in
                    Section("Hole \(h.number)") {
                        Stepper("파: \(h.par)", value: $h.par, in: 3...5)
                        Stepper("타수: \(h.strokes)", value: $h.strokes, in: 1...12)
                        Stepper("퍼팅: \(h.putts)", value: $h.putts, in: 0...6)
                        if h.par > 3 { Toggle("페어웨이 안착", isOn: $h.fairwayHit) }
                        Toggle("그린 적중 (GIR)", isOn: $h.gir)
                    }
                }
            }
            .navigationTitle("새 라운드")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: save)
                        .disabled(courseName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let record = RoundRecord(
            date: date, courseName: courseName,
            totalScore: totalScore, totalPutts: totalPutts,
            fairwaysHit: fairwaysHit, totalFairways: fairwayHoles.count,
            greensInRegulation: gir, driverDistance: driverDistance,
            courseRating: courseRating, slopeRating: max(slopeRating, 55),
            dataSource: .manual, scorecardImageData: imageData)
        modelContext.insert(record)
        record.holes = holes.map {
            HoleScore(holeNumber: $0.number, par: $0.par, strokes: $0.strokes,
                      putts: $0.putts, fairwayHit: $0.fairwayHit, greenInRegulation: $0.gir)
        }
        dismiss()
    }
}

// MARK: - 상세 + 이미지 확대
struct RecordDetailView: View {
    let record: RoundRecord
    @State private var showFullImage = false
    @Query(sort: \WatchActivity.startTime) private var watchActivities: [WatchActivity]

    private var sameDayWatch: [WatchActivity] {
        watchActivities.filter { Calendar.current.isDate($0.startTime, inSameDayAs: record.date) }
    }

    var body: some View {
        List {
            Section("라운드 정보") {
                LabeledContent("골프장", value: record.courseName)
                LabeledContent("날짜", value: record.date.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("총 스코어", value: "\(record.totalScore)타")
                LabeledContent("총 퍼팅", value: "\(record.totalPutts)개")
                LabeledContent("페어웨이", value: "\(record.fairwaysHit)/\(record.totalFairways)")
                LabeledContent("GIR", value: "\(record.greensInRegulation)/18")
            }

            if !sameDayWatch.isEmpty {
                Section("같은 날 워치 기록") {
                    ForEach(sameDayWatch) { a in
                        NavigationLink(destination: WatchActivityDetailView(activity: a)) {
                            Text("\(a.sport) · \(formatDuration(a.durationSeconds)) · \(String(format: "%.1f", a.distanceMeters / 1000))km")
                                .font(.subheadline)
                        }
                    }
                }
            }

            if let holes = record.holes, !holes.isEmpty {
                Section("홀별 기록") {
                    ForEach(holes.sorted { $0.holeNumber < $1.holeNumber }) { h in
                        HStack {
                            Text("\(h.holeNumber)번 (파\(h.par))")
                            Spacer()
                            Text("\(h.strokes)타 · 퍼팅 \(h.putts)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }

            if let data = record.scorecardImageData, let img = UIImage(data: data) {
                Section("스코어카드 사진") {
                    Image(uiImage: img).resizable().scaledToFit()
                        .onTapGesture { showFullImage = true }
                }
            }
        }
        .navigationTitle("상세 기록")
        .fullScreenCover(isPresented: $showFullImage) {
            if let data = record.scorecardImageData, let img = UIImage(data: data) {
                FullScreenImageViewer(uiImage: img)
            }
        }
    }
}

struct FullScreenImageViewer: View {
    let uiImage: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: uiImage)
                .resizable().scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnifyGesture()
                        .onChanged { scale = min(max(1, lastScale * $0.magnification), 6) }
                        .onEnded { _ in lastScale = scale }
                )
                .onTapGesture(count: 2) { withAnimation { scale = 1; lastScale = 1 } }
            Button("닫기") { dismiss() }
                .padding().foregroundStyle(.white)
        }
    }
}

// MARK: - 통계
struct GolfStatisticsView: View {
    @Query(filter: #Predicate<RoundRecord> { $0.isArchived == false })
    private var records: [RoundRecord]

    var body: some View {
        let s = GolfStatisticsAnalyzer.summary(from: records)
        List {
            Section("핸디캡") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("핸디캡 인덱스").font(.subheadline).foregroundStyle(.secondary)
                        Text(s.handicapIndex.map { String(format: "%.1f", $0) } ?? "-")
                            .font(.system(size: 34, weight: .bold)).foregroundStyle(.blue)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("총 라운드").font(.subheadline).foregroundStyle(.secondary)
                        Text("\(s.totalRounds)회").font(.title2).bold()
                    }
                }
                if s.handicapIndex == nil {
                    Text("라운드 3회 이상 기록하면 계산됩니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("스코어 / 숏게임") {
                LabeledContent("평균 스코어", value: String(format: "%.1f타", s.averageScore))
                LabeledContent("베스트 스코어", value: "\(s.bestScore)타")
                LabeledContent("평균 퍼팅", value: String(format: "%.1f개", s.averagePutts))
                LabeledContent("그린 적중률", value: String(format: "%.1f%%", s.girAccuracy))
            }
            Section("티샷") {
                LabeledContent("페어웨이 안착률", value: String(format: "%.1f%%", s.fairwayAccuracy))
                LabeledContent("평균 드라이버 비거리",
                               value: s.averageDriverDistance > 0 ? String(format: "%.0fm", s.averageDriverDistance) : "-")
            }
        }
        .navigationTitle("종합 분석")
    }
}

// MARK: - 데이터 관리 (CSV / FIT)
struct DataManagementView: View {
    private enum ImportKind { case csv, fit }

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<RoundRecord> { $0.isArchived == false },
           sort: \RoundRecord.date)
    private var records: [RoundRecord]
    @State private var importing = false
    @State private var kind: ImportKind = .csv
    @State private var message: String?

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var allowedTypes: [UTType] {
        kind == .fit
            ? [UTType(filenameExtension: "fit") ?? .data, .data]
            : [.commaSeparatedText, .plainText]
    }

    private var csv: String {
        var lines = ["date,course,score,putts,fairways_hit,fairways_total,gir,rating,slope"]
        for r in records {
            let name = r.courseName.replacingOccurrences(of: ",", with: " ")
            lines.append("\(Self.df.string(from: r.date)),\(name),\(r.totalScore),\(r.totalPutts),\(r.fairwaysHit),\(r.totalFairways),\(r.greensInRegulation),\(r.courseRating),\(r.slopeRating)")
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        List {
            Section("스코어 기록 (CSV)") {
                ShareLink(item: csv, subject: Text("골프 기록 백업")) {
                    Label("CSV로 내보내기 (\(records.count)건)", systemImage: "square.and.arrow.up")
                }
                Button { kind = .csv; importing = true } label: {
                    Label("CSV 가져오기", systemImage: "square.and.arrow.down")
                }
            }
            Section("워치 활동 (FIT)") {
                Button { kind = .fit; importing = true } label: {
                    Label("FIT 파일 가져오기", systemImage: "applewatch")
                }
                Text("경로, 심박, 시간, 거리, 칼로리를 가져옵니다. 홀별 타수는 FIT에 없어 직접 입력합니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let message {
                Section { Text(message).font(.footnote) }
            }
            Section("CSV 형식") {
                Text("date(yyyy-MM-dd), course, score, putts, fairways_hit, fairways_total, gir, rating, slope")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("데이터 관리")
        .fileImporter(isPresented: $importing, allowedContentTypes: allowedTypes) { result in
            guard case .success(let url) = result else { return }
            switch kind {
            case .csv: importCSV(url)
            case .fit: importFIT(url)
            }
        }
    }

    private func importFIT(_ url: URL) {
        do {
            if try WatchActivity.importFIT(from: url, into: modelContext) != nil {
                message = "워치 활동 1건을 가져왔습니다."
            } else {
                message = "이미 가져온 활동입니다."
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func importCSV(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            message = "파일을 읽지 못했습니다."; return
        }
        var count = 0
        for line in text.split(whereSeparator: \.isNewline).dropFirst() {
            let c = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard c.count >= 7, let d = Self.df.date(from: c[0]),
                  let score = Int(c[2]), let putts = Int(c[3]),
                  let fh = Int(c[4]), let ft = Int(c[5]), let gir = Int(c[6]) else { continue }
            let rating = c.count > 7 ? Double(c[7]) ?? 72 : 72
            let slope = c.count > 8 ? Double(c[8]) ?? 113 : 113
            modelContext.insert(RoundRecord(date: d, courseName: c[1], totalScore: score, totalPutts: putts,
                fairwaysHit: fh, totalFairways: ft, greensInRegulation: gir,
                courseRating: rating, slopeRating: slope, dataSource: .csv))
            count += 1
        }
        message = "\(count)건을 가져왔습니다."
    }
}
