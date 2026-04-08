import BatchCLI
import BatchModels
import BatchSupport
import Testing

@Test("generate 参数解析使用默认值")
func parseGenerateOptionsWithDefaults() throws {
    let options = try GenerateCommandOptions.parse(arguments: [
        "--epub", "/tmp/book.epub",
        "--output", "/tmp/out"
    ])

    #expect(options.epubPath == "/tmp/book.epub")
    #expect(options.inputDirectoryPath == nil)
    #expect(options.outputPath == "/tmp/out")
    #expect(options.targetHighlightCount == 20)
    #expect(options.language == "zh-Hans")
    #expect(options.style == .white)
    #expect(options.providerConfigPath == nil)
    #expect(options.overwritePolicy == .resume)
    #expect(options.profileDisplayName == "Reader")
    #expect(options.profileAvatarPath == nil)
    #expect(options.timeZoneIdentifier == nil)
}

@Test("generate 支持 --key=value 形式")
func parseGenerateOptionsWithInlineValues() throws {
    let options = try GenerateCommandOptions.parse(arguments: [
        "--epub=/tmp/book.epub",
        "--output=/tmp/out",
        "--highlights=12",
        "--language=en",
        "--style=black",
        "--profile-name=Alice",
        "--profile-avatar=/tmp/avatar.png",
        "--timezone=Asia/Shanghai",
        "--provider-config=/tmp/ai.json",
        "--overwrite-policy=replace"
    ])

    #expect(options.targetHighlightCount == 12)
    #expect(options.language == "en")
    #expect(options.style == .black)
    #expect(options.profileDisplayName == "Alice")
    #expect(options.profileAvatarPath == "/tmp/avatar.png")
    #expect(options.timeZoneIdentifier == "Asia/Shanghai")
    #expect(options.providerConfigPath == "/tmp/ai.json")
    #expect(options.overwritePolicy == .replace)
}

@Test("generate profile-name 空白时回退为 Reader")
func parseGenerateOptionsNormalizesProfileName() throws {
    let options = try GenerateCommandOptions.parse(arguments: [
        "--epub=/tmp/book.epub",
        "--output=/tmp/out",
        "--profile-name=   "
    ])
    let config = try options.toRunConfig()
    #expect(config.profileDisplayName == "Reader")
}

@Test("generate timezone 会透传到运行配置")
func parseGenerateOptionsKeepsTimezone() throws {
    let options = try GenerateCommandOptions.parse(arguments: [
        "--epub=/tmp/book.epub",
        "--output=/tmp/out",
        "--timezone=America/Los_Angeles"
    ])

    let config = try options.toRunConfig()
    #expect(config.timeZoneIdentifier == "America/Los_Angeles")
}

@Test("generate 支持 input-dir 模式")
func parseGenerateOptionsForInputDirectory() throws {
    let options = try GenerateCommandOptions.parse(arguments: [
        "--input-dir", "/tmp/books",
        "--output", "/tmp/out",
        "--highlights", "15"
    ])

    #expect(options.epubPath == nil)
    #expect(options.inputDirectoryPath == "/tmp/books")
    #expect(options.outputPath == "/tmp/out")
    #expect(options.targetHighlightCount == 15)
}

@Test("generate --help 不强制校验必填参数")
func parseGenerateOptionsWithHelpFlag() throws {
    let options = try GenerateCommandOptions.parse(arguments: ["--help"])
    #expect(options.showHelp)
}

@Test("generate highlights 必须为正整数")
func parseGenerateOptionsInvalidHighlights() {
    do {
        _ = try GenerateCommandOptions.parse(arguments: [
            "--epub", "/tmp/book.epub",
            "--output", "/tmp/out",
            "--highlights", "0"
        ])
        Issue.record("expected invalidIntegerOption")
    } catch let error as BatchError {
        #expect(error == .invalidIntegerOption(name: "--highlights", value: "0"))
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("generate overwrite-policy 必须为受支持值")
func parseGenerateOptionsInvalidOverwritePolicy() {
    do {
        _ = try GenerateCommandOptions.parse(arguments: [
            "--epub", "/tmp/book.epub",
            "--output", "/tmp/out",
            "--overwrite-policy", "merge"
        ])
        Issue.record("expected invalidOption")
    } catch let error as BatchError {
        #expect(error == .invalidOption("--overwrite-policy=merge"))
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("generate timezone 必须为有效时区")
func parseGenerateOptionsRejectsInvalidTimezone() {
    do {
        let options = try GenerateCommandOptions.parse(arguments: [
            "--epub", "/tmp/book.epub",
            "--output", "/tmp/out",
            "--timezone", "Mars/Olympus"
        ])
        _ = try options.toRunConfig()
        Issue.record("expected invalidOption")
    } catch let error as BatchError {
        #expect(error == .invalidOption("--timezone=Mars/Olympus"))
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("generate 要求 --epub 和 --input-dir 二选一")
func parseGenerateOptionsRequiresOneInputMode() {
    do {
        _ = try GenerateCommandOptions.parse(arguments: [
            "--output", "/tmp/out"
        ])
        Issue.record("expected missingRequiredOption")
    } catch let error as BatchError {
        #expect(error == .missingRequiredOption("--epub or --input-dir"))
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("generate 不允许同时传 --epub 和 --input-dir")
func parseGenerateOptionsRejectsMixedInputMode() {
    do {
        _ = try GenerateCommandOptions.parse(arguments: [
            "--epub", "/tmp/book.epub",
            "--input-dir", "/tmp/books",
            "--output", "/tmp/out"
        ])
        Issue.record("expected invalidOption")
    } catch let error as BatchError {
        #expect(error == .invalidOption("--epub and --input-dir cannot be used together"))
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}
