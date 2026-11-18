// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// A reference to a project or activity. Kimai sends either a bare id or an
/// expanded object depending on the endpoint; both are decoded.
struct KimaiRef: Equatable {
    var id: Int
    var name: String?
    /// Customer name for projects, project name for activities (when known).
    var parent: String?
    /// Project colour (`#rrggbb`) if Kimai sent one. Unvalidated.
    var color: String?
}

extension KimaiRef: Decodable {
    init(from decoder: Decoder) throws {
        // Either a bare number ...
        if let single = try? decoder.singleValueContainer(), let id = try? single.decode(Int.self) {
            self.init(id: id, name: nil, parent: nil, color: nil)
            return
        }
        // ... or an expanded object.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(Int.self, forKey: .id)
        let name = try? c.decode(String.self, forKey: .name)
        let color = try? c.decode(String.self, forKey: .color)
        var parent = try? c.decode(String.self, forKey: .parentTitle)
        if parent == nil, let cust = try? c.decode(Nested.self, forKey: .customer) { parent = cust.name }
        if parent == nil, let proj = try? c.decode(Nested.self, forKey: .project) { parent = proj.name }
        self.init(id: id, name: name, parent: parent, color: color)
    }

    private struct Nested: Decodable { var name: String? }
    private enum CodingKeys: String, CodingKey {
        case id, name, color, parentTitle, customer, project
    }
}

/// A timesheet entry. `end == nil` means it is running.
struct Timesheet: Decodable, Equatable, Identifiable {
    var id: Int
    var begin: Date
    var end: Date?
    var project: KimaiRef
    var activity: KimaiRef
    var description: String?

    var isRunning: Bool { end == nil }

    enum CodingKeys: String, CodingKey { case id, begin, end, project, activity, description }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        begin = try KimaiTime.parse(c.decode(String.self, forKey: .begin))
        if let s = try? c.decode(String.self, forKey: .end), !s.isEmpty {
            end = try KimaiTime.parse(s)
        } else {
            end = nil
        }
        project = try c.decode(KimaiRef.self, forKey: .project)
        activity = try c.decode(KimaiRef.self, forKey: .activity)
        description = try? c.decode(String.self, forKey: .description)
    }
}

struct Project: Decodable, Identifiable, Equatable {
    var id: Int
    var name: String
    var customer: String?
    var visible: Bool
    var color: String?

    enum CodingKeys: String, CodingKey {
        case id, name, visible, color
        case customer = "parentTitle"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        customer = try? c.decode(String.self, forKey: .customer)
        visible = (try? c.decode(Bool.self, forKey: .visible)) ?? true
        color = try? c.decode(String.self, forKey: .color)
    }
}

struct Activity: Decodable, Identifiable, Equatable {
    var id: Int
    var name: String
    var visible: Bool

    enum CodingKeys: String, CodingKey { case id, name, visible }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        visible = (try? c.decode(Bool.self, forKey: .visible)) ?? true
    }
}

struct KimaiUser: Decodable {
    var id: Int
    var username: String?
    var timezone: String?
}

struct KimaiVersion: Decodable {
    var version: String
}

/// What to start.
struct StartRequest: Equatable {
    var project: Int
    var activity: Int
    var description: String?
}
