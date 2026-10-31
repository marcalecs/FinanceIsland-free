import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor AssistantDatabase {
    static let shared = AssistantDatabase()

    private var db: OpaquePointer?

    init(path: String? = nil) {
        let file = path ?? Self.defaultPath()
        if sqlite3_open_v2(file, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            AppLog.write("SQLite open failed:", String(cString: sqlite3_errmsg(db)))
            db = nil
        }
        let schema = """
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS candles (
            source TEXT NOT NULL, symbol TEXT NOT NULL, interval TEXT NOT NULL,
            open_time INTEGER NOT NULL,
            open REAL NOT NULL, high REAL NOT NULL, low REAL NOT NULL, close REAL NOT NULL, volume REAL NOT NULL,
            PRIMARY KEY (source, symbol, interval, open_time)
        ) WITHOUT ROWID;
        CREATE TABLE IF NOT EXISTS signals (
            item TEXT NOT NULL, interval TEXT NOT NULL, ts INTEGER NOT NULL,
            signal TEXT NOT NULL, score REAL NOT NULL, risk REAL, price REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS signals_item ON signals (item, interval, ts);
        CREATE TABLE IF NOT EXISTS insights (
            item TEXT NOT NULL, provider TEXT NOT NULL, ts INTEGER NOT NULL, body TEXT NOT NULL,
            PRIMARY KEY (item, provider)
        );
        CREATE TABLE IF NOT EXISTS daily_cache (
            key TEXT PRIMARY KEY, ts INTEGER NOT NULL, source TEXT NOT NULL, body BLOB NOT NULL
        );
        CREATE TABLE IF NOT EXISTS headlines (
            item TEXT NOT NULL, title TEXT NOT NULL, published INTEGER NOT NULL, score REAL NOT NULL,
            publisher TEXT NOT NULL DEFAULT '', link TEXT NOT NULL DEFAULT '',
            PRIMARY KEY (item, title)
        );
        CREATE INDEX IF NOT EXISTS headlines_item ON headlines (item, published);
        CREATE TABLE IF NOT EXISTS engine_predictions (
            run_id TEXT NOT NULL, ticker TEXT NOT NULL, as_of TEXT NOT NULL,
            p_sell REAL NOT NULL, p_hold REAL NOT NULL, p_buy REAL NOT NULL,
            verdict TEXT NOT NULL, regime TEXT NOT NULL, position_pct REAL NOT NULL, created INTEGER NOT NULL,
            PRIMARY KEY (run_id, ticker)
        );
        """
        if let db { sqlite3_exec(db, schema, nil, nil, nil) }
    }

    static func defaultPath() -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FinanceIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("assistant.sqlite").path
    }

    func cachedInsight(item: WatchItem, provider: String, maxAge: TimeInterval) -> String? {
        guard let db else { return nil }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT ts, body FROM insights WHERE item = ? AND provider = ?", -1, &st, nil) == SQLITE_OK
        else { return nil }
        defer { sqlite3_finalize(st) }
        bind(st, 1, item.id); bind(st, 2, provider)
        guard sqlite3_step(st) == SQLITE_ROW else { return nil }
        let ts = Date(timeIntervalSince1970: Double(sqlite3_column_int64(st, 0)))
        return Date().timeIntervalSince(ts) <= maxAge ? text(st, 1) : nil
    }

    func storeInsight(item: WatchItem, provider: String, body: String) {
        guard let db else { return }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO insights (item, provider, ts, body) VALUES (?, ?, ?, ?)",
                                 -1, &st, nil) == SQLITE_OK else { return }
        bind(st, 1, item.id); bind(st, 2, provider)
        sqlite3_bind_int64(st, 3, Int64(Date().timeIntervalSince1970))
        bind(st, 4, body)
        sqlite3_step(st)
        sqlite3_finalize(st)
    }


    func eraseAll() {
        guard let db else { return }
        sqlite3_exec(db, """
        DELETE FROM candles; DELETE FROM signals; DELETE FROM insights;
        DELETE FROM daily_cache; DELETE FROM headlines; DELETE FROM engine_predictions; VACUUM;
        """, nil, nil, nil)
    }

    private func bind(_ st: OpaquePointer?, _ i: Int32, _ s: String) {
        sqlite3_bind_text(st, i, s, -1, SQLITE_TRANSIENT)
    }

    private func text(_ st: OpaquePointer?, _ col: Int32) -> String {
        guard let c = sqlite3_column_text(st, col) else { return "" }
        return String(cString: c)
    }
}
