import Testing
@testable import TokensCore

@Test func changeLogParserFindsVersionSection() {
    let markdown = """
    # Changelog

    ## 0.0.29
    - First item
    - Second item

    ## 0.0.28
    - Older item
    """

    let items = ChangeLogParser.items(in: markdown, version: "0.0.29")
    #expect(items == ["First item", "Second item"])
}

@Test func changeLogParserStripsDevSuffix() {
    let markdown = """
    ## 0.0.28
    - Stable feature
    """

    let items = ChangeLogParser.items(in: markdown, version: "0.0.28-dev")
    #expect(items == ["Stable feature"])
}

@Test func changeLogParserFallsBackToLatestSection() {
    let markdown = """
    ## 0.0.29
    - Newest feature

    ## 0.0.28
    - Stable feature
    """

    let items = ChangeLogParser.items(in: markdown, version: "9.9.9")
    #expect(items == ["Newest feature"])
}
