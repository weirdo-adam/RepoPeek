@testable import RepoPeek
import Testing

struct StatValueFormatterTests {
    @Test
    func `compact rounds thousands and millions`() {
        #expect(StatValueFormatter.compact(999) == "999")
        #expect(StatValueFormatter.compact(1249) == "1.2K")
        #expect(StatValueFormatter.compact(19499) == "19K")
        #expect(StatValueFormatter.compact(19500) == "20K")
        #expect(StatValueFormatter.compact(999_499) == "999K")
        #expect(StatValueFormatter.compact(999_500) == "1M")
        #expect(StatValueFormatter.compact(9_999_999) == "10M")
        #expect(StatValueFormatter.compact(19_500_000) == "20M")
        #expect(StatValueFormatter.compact(999_500_000) == "999M")
    }
}
