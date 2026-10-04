// Standalone test for Search Contacts' ranking and field filter, compiling the real model.
import Foundation

@main
struct ContactsTests {
    nonisolated(unsafe) static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if !condition {
            print("FAIL: \(label)")
            failures += 1
        }
    }

    static func field(_ kind: ContactField.Kind, _ label: String, _ value: String, _ position: Int) -> ContactField {
        ContactField(kind: kind, label: label, value: value, position: position)
    }

    static func main() {
        let ada = ContactCard(
            id: "ada", name: "Ada Lovelace", organization: "Analytical Engines", isCompany: false,
            fields: [
                field(.phone, "mobile", "(415) 555-1234", 0),
                field(.email, "work", "ada@engines.example", 1),
                field(.address, "home", "12 St James's Square, London", 2),
            ])
        let grace = ContactCard(
            id: "grace", name: "Grace Hopper", organization: "", isCompany: false,
            fields: [field(.email, "home", "amazing@navy.example", 0)])
        let engines = ContactCard(
            id: "engines", name: "Engines Ltd", organization: "Engines Ltd", isCompany: true, fields: [])
        let adair = ContactCard(
            id: "adair", name: "Bob Adair", organization: "Ada Analytics", isCompany: false, fields: [])
        let cards = [grace, engines, ada, adair]

        let all = ContactSearch.rank(cards, query: "  ")
        expect(all.map(\.id) == ["ada", "adair", "engines", "grace"], "an empty query lists every card A to Z")

        let ad = ContactSearch.rank(cards, query: "ada")
        expect(ad.first?.id == "ada", "a name hit leads")
        expect(ad.map(\.id).contains("adair"), "a surname hit on a word start still matches")
        expect(!ad.map(\.id).contains("grace"), "no hit leaves a card out")

        let engine = ContactSearch.rank(cards, query: "engines")
        expect(engine.first?.id == "engines", "a card named by the query beats one whose company matches")
        expect(engine.map(\.id).contains("ada"), "a company hit still lists the person")

        expect(ContactSearch.rank(cards, query: "navy").map(\.id) == ["grace"], "an email hit finds its card")
        expect(ContactSearch.rank(cards, query: "5551234").map(\.id) == ["ada"], "digits find a formatted number")
        expect(ContactSearch.rank(cards, query: "51").isEmpty, "two digits are too few to strip a number to its digits")
        expect(ContactSearch.rank(cards, query: "lvlc").isEmpty, "a loose subsequence matches nothing")

        let fields = ada.fields
        expect(ContactSearch.filter(fields, query: "").count == 3, "an empty filter keeps every field")
        expect(ContactSearch.filter(fields, query: "mobile").map(\.kind) == [.phone], "a label filters fields")
        expect(ContactSearch.filter(fields, query: "london").map(\.kind) == [.address], "a value filters fields")
        expect(ContactSearch.filter(fields, query: "1234").map(\.kind) == [.phone], "digits filter a number")

        expect(ada.subtitle == "Analytical Engines", "a person's subtitle is their company")
        expect(engines.subtitle == nil, "a company named by its own name has no subtitle")
        expect(grace.subtitle == "amazing@navy.example", "without a company the first email or number shows")
        expect(fields.map(\.id) == ["phone-0", "email-1", "address-2"], "field ids follow card order")

        if failures > 0 {
            print("\(failures) failure(s)")
            exit(1)
        }
        print("contacts: all passed")
    }
}
