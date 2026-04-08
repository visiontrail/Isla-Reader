import BatchCLI
import BatchSupport
import Testing

@Test("captions 参数解析支持 manifest")
func parseCaptionsOptionsWithManifest() throws {
    let options = try CaptionsCommandOptions.parse(arguments: [
        "--manifest", "/tmp/manifest.json"
    ])

    #expect(options.manifestPath == "/tmp/manifest.json")
    #expect(!options.showHelp)
}

@Test("captions --help 不强制校验必填参数")
func parseCaptionsOptionsWithHelp() throws {
    let options = try CaptionsCommandOptions.parse(arguments: ["--help"])
    #expect(options.showHelp)
}

@Test("captions 要求 --manifest")
func parseCaptionsOptionsRequiresManifest() {
    do {
        _ = try CaptionsCommandOptions.parse(arguments: [])
        Issue.record("expected missingRequiredOption")
    } catch let error as BatchError {
        #expect(error == .missingRequiredOption("--manifest"))
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("publish 参数解析支持 --manifest 和 --channel")
func parsePublishOptionsWithInlineValues() throws {
    let options = try PublishCommandOptions.parse(arguments: [
        "--manifest=/tmp/manifest.json",
        "--channel=xiaohongshu"
    ])

    #expect(options.manifestPath == "/tmp/manifest.json")
    #expect(options.channel == "xiaohongshu")
    #expect(!options.showHelp)
}

@Test("publish 要求 --channel")
func parsePublishOptionsRequiresChannel() {
    do {
        _ = try PublishCommandOptions.parse(arguments: [
            "--manifest", "/tmp/manifest.json"
        ])
        Issue.record("expected missingRequiredOption")
    } catch let error as BatchError {
        #expect(error == .missingRequiredOption("--channel"))
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}
