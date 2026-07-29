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

@Test func changeLogParserParseAllSectionsPreservesOrder() {
    let markdown = """
    ## 0.0.29
    - New

    ## 0.0.28
    - Old
    """

    let sections = ChangeLogParser.parseAllSections(in: markdown)
    #expect(sections.map(\.version) == ["0.0.29", "0.0.28"])
    #expect(sections[0].items == ["New"])
}

@Test func changeLogParserDisplaySectionsShowsLastThree() {
    let markdown = """
    ## 0.0.30
    - A

    ## 0.0.29
    - B

    ## 0.0.28
    - C

    ## 0.0.27
    - D
    """

    let sections = ChangeLogParser.displaySections(in: markdown, limit: 3)
    #expect(sections.map(\.version) == ["0.0.30", "0.0.29", "0.0.28"])
}

@Test func changeLogParserDisplaySectionsPrefersIncomingVersion() {
    let markdown = """
    ## 0.0.28
    - Shipped
    """

    let notes = """
    ## What's new in 0.0.29

    - Incoming feature
    """

    let sections = ChangeLogParser.displaySections(
        in: markdown,
        limit: 3,
        highlightVersion: "0.0.29",
        releaseNotes: notes
    )
    #expect(sections.map(\.version) == ["0.0.29", "0.0.28"])
    #expect(sections[0].items == ["Incoming feature"])
}

@Test func changeLogParserItemsFromReleaseNotes() {
    let notes = """
  ## What's new in 0.0.29

  - One
  - Two
  """
    #expect(ChangeLogParser.itemsFromReleaseNotes(notes) == ["One", "Two"])
}
