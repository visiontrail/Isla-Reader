import Foundation

public enum ShareCardStyle: String, CaseIterable, Codable, Sendable {
    case none
    case white
    case black
}

public struct BatchBookMetadata: Equatable, Codable, Sendable {
    public var title: String
    public var author: String?
    public var language: String?
    public var coverImageData: Data?

    public init(title: String, author: String?, language: String?, coverImageData: Data? = nil) {
        self.title = title
        self.author = author
        self.language = language
        self.coverImageData = coverImageData
    }
}

public struct BatchBookChapter: Equatable, Codable, Sendable {
    public var title: String
    public var content: String
    public var order: Int
    public var sourceHref: String?

    public init(title: String, content: String, order: Int, sourceHref: String?) {
        self.title = title
        self.content = content
        self.order = order
        self.sourceHref = sourceHref
    }
}

public struct BatchBook: Equatable, Codable, Sendable {
    public var metadata: BatchBookMetadata
    public var chapters: [BatchBookChapter]

    public init(metadata: BatchBookMetadata, chapters: [BatchBookChapter]) {
        self.metadata = metadata
        self.chapters = chapters
    }
}

public struct BookExcerpt: Equatable, Codable, Sendable {
    public var id: String
    public var chapterOrder: Int
    public var chapterTitle: String
    public var windowIndex: Int
    public var text: String
    public var textHash: String
    public var wordCount: Int

    public init(
        id: String,
        chapterOrder: Int,
        chapterTitle: String,
        windowIndex: Int,
        text: String,
        textHash: String,
        wordCount: Int
    ) {
        self.id = id
        self.chapterOrder = chapterOrder
        self.chapterTitle = chapterTitle
        self.windowIndex = windowIndex
        self.text = text
        self.textHash = textHash
        self.wordCount = wordCount
    }
}

public struct BatchRunConfig: Equatable, Sendable {
    public enum OverwritePolicy: String, CaseIterable, Codable, Sendable {
        case resume
        case replace
    }

    public var epubPath: String
    public var outputPath: String
    public var targetHighlightCount: Int
    public var language: String
    public var style: ShareCardStyle
    public var providerConfigPath: String?
    public var overwritePolicy: OverwritePolicy
    public var profileDisplayName: String
    public var profileAvatarPath: String?
    public var timeZoneIdentifier: String?

    public init(
        epubPath: String,
        outputPath: String,
        targetHighlightCount: Int,
        language: String,
        style: ShareCardStyle,
        providerConfigPath: String?,
        overwritePolicy: OverwritePolicy = .resume,
        profileDisplayName: String = "Reader",
        profileAvatarPath: String? = nil,
        timeZoneIdentifier: String? = nil
    ) {
        self.epubPath = epubPath
        self.outputPath = outputPath
        self.targetHighlightCount = targetHighlightCount
        self.language = language
        self.style = style
        self.providerConfigPath = providerConfigPath
        self.overwritePolicy = overwritePolicy
        self.profileDisplayName = profileDisplayName
        self.profileAvatarPath = profileAvatarPath
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

public struct BatchAIProviderConfiguration: Equatable, Codable, Sendable {
    public var endpoint: String
    public var apiKey: String
    public var model: String
    public var timeoutSeconds: Double
    public var maxRetryCount: Int

    public init(
        endpoint: String,
        apiKey: String,
        model: String,
        timeoutSeconds: Double = 45,
        maxRetryCount: Int = 2
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
        self.timeoutSeconds = timeoutSeconds
        self.maxRetryCount = maxRetryCount
    }
}

public struct BatchStage1Request: Equatable, Sendable {
    public var bookMetadata: BatchBookMetadata
    public var excerpt: BookExcerpt
    public var outputLanguage: String

    public init(bookMetadata: BatchBookMetadata, excerpt: BookExcerpt, outputLanguage: String) {
        self.bookMetadata = bookMetadata
        self.excerpt = excerpt
        self.outputLanguage = outputLanguage
    }
}

public struct BatchStage1CandidateDraft: Equatable, Codable, Sendable {
    public var highlightText: String
    public var noteText: String
    public var tags: [String]
    public var score: Double
    public var reason: String

    public init(
        highlightText: String,
        noteText: String,
        tags: [String],
        score: Double,
        reason: String
    ) {
        self.highlightText = highlightText
        self.noteText = noteText
        self.tags = tags
        self.score = score
        self.reason = reason
    }
}

public struct BatchStage1ExtractionResult: Equatable, Sendable {
    public var promptText: String
    public var responseText: String
    public var candidates: [BatchStage1CandidateDraft]
    public var attemptCount: Int

    public init(
        promptText: String,
        responseText: String,
        candidates: [BatchStage1CandidateDraft],
        attemptCount: Int
    ) {
        self.promptText = promptText
        self.responseText = responseText
        self.candidates = candidates
        self.attemptCount = attemptCount
    }
}

public struct Stage1Candidate: Equatable, Codable, Sendable {
    public var id: String
    public var excerptId: String
    public var chapterOrder: Int
    public var chapterTitle: String
    public var windowIndex: Int
    public var excerptHash: String
    public var highlightText: String
    public var noteText: String
    public var tags: [String]
    public var score: Double
    public var reason: String

    public init(
        id: String,
        excerptId: String,
        chapterOrder: Int,
        chapterTitle: String,
        windowIndex: Int,
        excerptHash: String,
        highlightText: String,
        noteText: String,
        tags: [String],
        score: Double,
        reason: String
    ) {
        self.id = id
        self.excerptId = excerptId
        self.chapterOrder = chapterOrder
        self.chapterTitle = chapterTitle
        self.windowIndex = windowIndex
        self.excerptHash = excerptHash
        self.highlightText = highlightText
        self.noteText = noteText
        self.tags = tags
        self.score = score
        self.reason = reason
    }
}

public struct BatchStage2Request: Equatable, Sendable {
    public var bookMetadata: BatchBookMetadata
    public var candidates: [Stage1Candidate]
    public var outputLanguage: String
    public var targetCount: Int

    public init(
        bookMetadata: BatchBookMetadata,
        candidates: [Stage1Candidate],
        outputLanguage: String,
        targetCount: Int
    ) {
        self.bookMetadata = bookMetadata
        self.candidates = candidates
        self.outputLanguage = outputLanguage
        self.targetCount = targetCount
    }
}

public struct BatchStage2SelectionDraft: Equatable, Codable, Sendable {
    public var candidateId: String
    public var rank: Int?
    public var score: Double?
    public var reason: String

    public init(candidateId: String, rank: Int?, score: Double?, reason: String) {
        self.candidateId = candidateId
        self.rank = rank
        self.score = score
        self.reason = reason
    }
}

public struct BatchStage2SelectionResult: Equatable, Sendable {
    public var promptText: String
    public var responseText: String
    public var selections: [BatchStage2SelectionDraft]
    public var attemptCount: Int

    public init(
        promptText: String,
        responseText: String,
        selections: [BatchStage2SelectionDraft],
        attemptCount: Int
    ) {
        self.promptText = promptText
        self.responseText = responseText
        self.selections = selections
        self.attemptCount = attemptCount
    }
}

public struct SelectedHighlightItem: Equatable, Codable, Sendable {
    public var id: String
    public var rank: Int
    public var candidateId: String
    public var excerptId: String
    public var chapterOrder: Int
    public var chapterTitle: String
    public var windowIndex: Int
    public var excerptHash: String
    public var highlightText: String
    public var noteText: String
    public var tags: [String]
    public var candidateScore: Double
    public var stage2Score: Double?
    public var selectionReason: String
    public var imagePath: String?
    public var renderError: String?

    public init(
        id: String,
        rank: Int,
        candidateId: String,
        excerptId: String,
        chapterOrder: Int,
        chapterTitle: String,
        windowIndex: Int,
        excerptHash: String,
        highlightText: String,
        noteText: String,
        tags: [String],
        candidateScore: Double,
        stage2Score: Double?,
        selectionReason: String,
        imagePath: String? = nil,
        renderError: String? = nil
    ) {
        self.id = id
        self.rank = rank
        self.candidateId = candidateId
        self.excerptId = excerptId
        self.chapterOrder = chapterOrder
        self.chapterTitle = chapterTitle
        self.windowIndex = windowIndex
        self.excerptHash = excerptHash
        self.highlightText = highlightText
        self.noteText = noteText
        self.tags = tags
        self.candidateScore = candidateScore
        self.stage2Score = stage2Score
        self.selectionReason = selectionReason
        self.imagePath = imagePath
        self.renderError = renderError
    }
}

public struct Stage2SelectionOutput: Equatable, Codable, Sendable {
    public var mode: String
    public var targetCount: Int
    public var stage1CandidateCount: Int
    public var deduplicatedCandidateCount: Int
    public var prescreenCandidateCount: Int
    public var selected: [SelectedHighlightItem]

    public init(
        mode: String,
        targetCount: Int,
        stage1CandidateCount: Int,
        deduplicatedCandidateCount: Int,
        prescreenCandidateCount: Int,
        selected: [SelectedHighlightItem]
    ) {
        self.mode = mode
        self.targetCount = targetCount
        self.stage1CandidateCount = stage1CandidateCount
        self.deduplicatedCandidateCount = deduplicatedCandidateCount
        self.prescreenCandidateCount = prescreenCandidateCount
        self.selected = selected
    }
}

public struct BatchManifest: Equatable, Codable, Sendable {
    public var runId: String
    public var generatedAt: String
    public var sourceFile: String
    public var book: BatchManifestBook
    public var config: BatchManifestConfig
    public var stats: BatchManifestStats
    public var items: [BatchManifestItem]
    public var extensions: BatchManifestExtensions?

    public init(
        runId: String,
        generatedAt: String,
        sourceFile: String,
        book: BatchManifestBook,
        config: BatchManifestConfig,
        stats: BatchManifestStats,
        items: [BatchManifestItem],
        extensions: BatchManifestExtensions? = nil
    ) {
        self.runId = runId
        self.generatedAt = generatedAt
        self.sourceFile = sourceFile
        self.book = book
        self.config = config
        self.stats = stats
        self.items = items
        self.extensions = extensions
    }

    private enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case generatedAt = "generated_at"
        case sourceFile = "source_file"
        case book
        case config
        case stats
        case items
        case extensions
    }
}

public struct BatchManifestExtensions: Equatable, Codable, Sendable {
    public var captions: BatchManifestCaptionsExtension
    public var publish: BatchManifestPublishExtension

    public init(
        captions: BatchManifestCaptionsExtension,
        publish: BatchManifestPublishExtension
    ) {
        self.captions = captions
        self.publish = publish
    }

    public static var reserved: BatchManifestExtensions {
        BatchManifestExtensions(
            captions: BatchManifestCaptionsExtension(status: "reserved", outputFile: "captions.jsonl"),
            publish: BatchManifestPublishExtension(
                status: "reserved",
                defaultChannel: nil,
                availableChannels: []
            )
        )
    }
}

public struct BatchManifestCaptionsExtension: Equatable, Codable, Sendable {
    public var status: String
    public var outputFile: String

    public init(status: String, outputFile: String) {
        self.status = status
        self.outputFile = outputFile
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case outputFile = "output_file"
    }
}

public struct BatchManifestPublishExtension: Equatable, Codable, Sendable {
    public var status: String
    public var defaultChannel: String?
    public var availableChannels: [String]

    public init(status: String, defaultChannel: String?, availableChannels: [String]) {
        self.status = status
        self.defaultChannel = defaultChannel
        self.availableChannels = availableChannels
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case defaultChannel = "default_channel"
        case availableChannels = "available_channels"
    }
}

public struct BatchManifestBook: Equatable, Codable, Sendable {
    public var title: String
    public var author: String?
    public var language: String?

    public init(title: String, author: String?, language: String?) {
        self.title = title
        self.author = author
        self.language = language
    }
}

public struct BatchManifestConfig: Equatable, Codable, Sendable {
    public var highlights: Int
    public var language: String
    public var style: String
    public var model: String
    public var overwritePolicy: String
    public var profileDisplayName: String?
    public var profileAvatarPath: String?
    public var timeZoneIdentifier: String?

    public init(
        highlights: Int,
        language: String,
        style: String,
        model: String,
        overwritePolicy: String,
        profileDisplayName: String? = nil,
        profileAvatarPath: String? = nil,
        timeZoneIdentifier: String? = nil
    ) {
        self.highlights = highlights
        self.language = language
        self.style = style
        self.model = model
        self.overwritePolicy = overwritePolicy
        self.profileDisplayName = profileDisplayName
        self.profileAvatarPath = profileAvatarPath
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    private enum CodingKeys: String, CodingKey {
        case highlights
        case language
        case style
        case model
        case overwritePolicy = "overwrite_policy"
        case profileDisplayName = "profile_display_name"
        case profileAvatarPath = "profile_avatar_path"
        case timeZoneIdentifier = "time_zone_identifier"
    }
}

public struct BatchManifestStats: Equatable, Codable, Sendable {
    public var chapters: Int
    public var windows: Int
    public var stage1Candidates: Int
    public var deduplicatedCandidates: Int
    public var stage2InputCandidates: Int
    public var finalItems: Int
    public var renderSuccessCount: Int
    public var renderFailureCount: Int

    public init(
        chapters: Int,
        windows: Int,
        stage1Candidates: Int,
        deduplicatedCandidates: Int,
        stage2InputCandidates: Int,
        finalItems: Int,
        renderSuccessCount: Int,
        renderFailureCount: Int
    ) {
        self.chapters = chapters
        self.windows = windows
        self.stage1Candidates = stage1Candidates
        self.deduplicatedCandidates = deduplicatedCandidates
        self.stage2InputCandidates = stage2InputCandidates
        self.finalItems = finalItems
        self.renderSuccessCount = renderSuccessCount
        self.renderFailureCount = renderFailureCount
    }

    private enum CodingKeys: String, CodingKey {
        case chapters
        case windows
        case stage1Candidates = "stage1_candidates"
        case deduplicatedCandidates = "deduplicated_candidates"
        case stage2InputCandidates = "stage2_input_candidates"
        case finalItems = "final_items"
        case renderSuccessCount = "render_success_count"
        case renderFailureCount = "render_failure_count"
    }
}

public struct BatchManifestItem: Equatable, Codable, Sendable {
    public var id: String
    public var rank: Int
    public var chapterTitle: String
    public var chapterOrder: Int
    public var sourceExcerpt: String
    public var highlightText: String
    public var noteText: String
    public var imagePath: String?
    public var score: Double
    public var tags: [String]
    public var sourceLocator: BatchManifestSourceLocator
    public var candidateId: String
    public var excerptId: String
    public var selectionReason: String
    public var renderError: String?

    public init(
        id: String,
        rank: Int,
        chapterTitle: String,
        chapterOrder: Int,
        sourceExcerpt: String,
        highlightText: String,
        noteText: String,
        imagePath: String?,
        score: Double,
        tags: [String],
        sourceLocator: BatchManifestSourceLocator,
        candidateId: String,
        excerptId: String,
        selectionReason: String,
        renderError: String?
    ) {
        self.id = id
        self.rank = rank
        self.chapterTitle = chapterTitle
        self.chapterOrder = chapterOrder
        self.sourceExcerpt = sourceExcerpt
        self.highlightText = highlightText
        self.noteText = noteText
        self.imagePath = imagePath
        self.score = score
        self.tags = tags
        self.sourceLocator = sourceLocator
        self.candidateId = candidateId
        self.excerptId = excerptId
        self.selectionReason = selectionReason
        self.renderError = renderError
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case rank
        case chapterTitle = "chapter_title"
        case chapterOrder = "chapter_order"
        case sourceExcerpt = "source_excerpt"
        case highlightText = "highlight_text"
        case noteText = "note_text"
        case imagePath = "image_path"
        case score
        case tags
        case sourceLocator = "source_locator"
        case candidateId = "candidate_id"
        case excerptId = "excerpt_id"
        case selectionReason = "selection_reason"
        case renderError = "render_error"
    }
}

public struct BatchManifestSourceLocator: Equatable, Codable, Sendable {
    public var chapterOrder: Int
    public var excerptIndex: Int
    public var excerptHash: String

    public init(chapterOrder: Int, excerptIndex: Int, excerptHash: String) {
        self.chapterOrder = chapterOrder
        self.excerptIndex = excerptIndex
        self.excerptHash = excerptHash
    }

    private enum CodingKeys: String, CodingKey {
        case chapterOrder = "chapter_order"
        case excerptIndex = "excerpt_index"
        case excerptHash = "excerpt_hash"
    }
}

public struct BatchGenerateResult: Equatable, Sendable {
    public enum Phase: String, Equatable, Sendable {
        case p0Scaffold
        case p1Chunking
        case p2Stage1Extraction
        case p3Stage2Selection
        case p4RenderedShareCards
        case p5ManifestAndRerun
    }

    public var phase: Phase
    public var outputDirectory: String
    public var runLogPath: String
    public var excerptsPath: String?
    public var candidatesPath: String?
    public var selectedPath: String?
    public var imagesDirectory: String?
    public var manifestPath: String?

    public init(
        phase: Phase,
        outputDirectory: String,
        runLogPath: String,
        excerptsPath: String? = nil,
        candidatesPath: String? = nil,
        selectedPath: String? = nil,
        imagesDirectory: String? = nil,
        manifestPath: String? = nil
    ) {
        self.phase = phase
        self.outputDirectory = outputDirectory
        self.runLogPath = runLogPath
        self.excerptsPath = excerptsPath
        self.candidatesPath = candidatesPath
        self.selectedPath = selectedPath
        self.imagesDirectory = imagesDirectory
        self.manifestPath = manifestPath
    }
}
