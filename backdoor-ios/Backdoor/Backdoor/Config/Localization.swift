import Foundation
import Observation
import SwiftUI

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case en, ja
    var id: String { rawValue }

    var label: String {
        switch self {
        case .en: return "English"
        case .ja: return "日本語"
        }
    }
}

@Observable
@MainActor
final class LanguageManager {
    static let shared = LanguageManager()
    private let storageKey = "app_language"

    var current: AppLanguage {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: storageKey) }
    }

    private init() {
        if let stored = UserDefaults.standard.string(forKey: storageKey),
           let lang = AppLanguage(rawValue: stored) {
            current = lang
        } else {
            let preferred = Locale.preferredLanguages.first ?? "en"
            current = preferred.hasPrefix("ja") ? .ja : .en
        }
    }

    /// Translate a key to the current language.
    func t(_ key: String) -> String {
        strings[current]?[key]
            ?? strings[.en]?[key]
            ?? key
    }

    /// Pick the right language from a (english, japanese?) pair.
    /// Falls back to the other language if the chosen one is empty.
    func pick(en: String, ja: String?) -> String {
        switch current {
        case .en:
            return en.isEmpty ? (ja ?? "") : en
        case .ja:
            if let ja, !ja.isEmpty { return ja }
            return en
        }
    }
}

// MARK: - Global helper for concise call sites
@MainActor
func tr(_ key: String) -> String { LanguageManager.shared.t(key) }

// MARK: - Translations dictionary
private let strings: [AppLanguage: [String: String]] = [
    .en: enStrings,
    .ja: jaStrings
]

// swiftlint:disable line_length
private let enStrings: [String: String] = [
    // Common
    "cancel": "Cancel",
    "save": "Save",
    "done": "Done",
    "delete": "Delete",
    "edit": "Edit",
    "create": "Create",
    "loading": "Loading",
    "error": "Error",
    "retry": "Retry",

    // Auth
    "app_subtitle": "Staff task board",
    "app_subtitle_signup": "Create your account",
    "sign_in": "Sign in",
    "sign_up": "Sign up",
    "sign_out": "Sign out",
    "sign_out_confirm": "Sign out?",
    "email": "Email",
    "password": "Password",
    "password_signup": "Password (6+ characters)",
    "your_name": "Your name",
    "create_account": "Create account",
    "signup_note": "By creating an account, a staff profile is made for you. An admin can approve and set your permissions.",
    "check_email": "Check your email to confirm your account, then sign in.",

    // Tabs
    "tab_today": "Today",
    "tab_mine": "Mine",
    "tab_admin": "Admin",

    // Task board
    "no_tasks_today": "No tasks today.",
    "no_tasks_mine": "No tasks assigned to you today.",
    "no_tasks": "No tasks",
    "tasks_done_progress": "%@/%@ done · %@%%",

    // Task completion
    "start": "Start",
    "complete": "Complete",
    "undo": "Undo",
    "take_photo": "Take photo",
    "choose_photo": "Choose photo",
    "add_note": "Add a note (optional)",
    "completion_photo": "Completion photo",

    // Task categories
    "cat_opening": "Opening",
    "cat_closing": "Closing",
    "cat_bar": "Bar",
    "cat_cleaning": "Cleaning",
    "cat_weekly": "Weekly",
    "cat_other": "Other",

    // Task priority
    "priority_low": "Low",
    "priority_normal": "Normal",
    "priority_high": "High",

    // Profile menu
    "edit_profile": "Edit profile",
    "profile": "Profile",
    "change_photo": "Change photo",
    "name": "Name",
    "language": "Language",

    // Admin
    "admin_overview": "Overview",
    "admin_tasks": "Tasks",
    "admin_staff": "Staff",
    "stat_total": "Total",
    "stat_done": "Done",
    "stat_open": "Open",
    "per_staff_today": "Per staff · today",
    "staff_signup_hint": "Staff sign up through the app — they appear here automatically.",
    "active": "Active",
    "inactive": "Off",
    "role_admin": "admin",
    "role_staff": "staff",

    // Task editor
    "new_task": "New task",
    "edit_task": "Edit task",
    "title_en": "Title (English)",
    "title_ja": "Title (日本語)",
    "category": "Category",
    "priority": "Priority",
    "assign_to": "Assign to",
    "assign_anyone": "Anyone",
    "recurring": "Recurring",
    "repeats": "Repeats",
    "repeat_daily": "Daily",
    "repeat_weekly": "Weekly",
    "repeat_monthly": "Monthly",
    "days": "Days",

    // Task status
    "status_pending": "Pending",
    "status_in_progress": "In Progress",
    "status_completed": "Done",

    // Time buckets
    "time_now": "Now",
    "time_upcoming": "Upcoming",
    "time_anytime": "Anytime",
    "time_done": "Done",
    "time_overdue": "Overdue",
    "target_time": "Target time",
    "target_time_optional": "Target time (optional)",
    "time_window_optional": "Time window (optional)",
    "start_time": "Start",
    "end_time": "End",
    "end_after_start": "End time must be after start time.",
    "by_prefix": "by",
    "anytime_clear": "Anytime",
    "set_time": "Set time",

    // Admin hours
    "admin_hours": "Hours",
    "hours_hint": "Set the weekly operating hours. Tasks won't generate on closed days.",
    "weekday_mon": "Monday",
    "weekday_tue": "Tuesday",
    "weekday_wed": "Wednesday",
    "weekday_thu": "Thursday",
    "weekday_fri": "Friday",
    "weekday_sat": "Saturday",
    "weekday_sun": "Sunday",
    "closed": "Closed",
    "closed_day": "Closed this day",
    "open_time": "Open",
    "close_time": "Close",
    "close_next_day_hint": "If close time is earlier than open time, it's assumed to be the next day.",
    "prep_buffer": "Pre-shift prep buffer",
    "prep_buffer_hint": "How many hours before open the business day activates (for morning prep tasks).",
    "grace_period": "Overtime grace period",
    "grace_period_hint": "If the venue runs late past close time, keep staff on the same business day for this many extra minutes.",
    "timezone": "Timezone",
    "timezone_hint": "The venue's local time zone. Used for every business-day calculation.",
    "search_timezone": "Search timezones",
    "operating_hours": "Operating hours",
    "next_day_label": "next day",
    "admin_history": "History",
    "history_filter_range": "Date",
    "history_filter_events": "Event",
    "history_filter_actor": "Staff",
    "history_range_today": "Today",
    "history_range_7d": "7 days",
    "history_range_30d": "30 days",
    "history_range_all": "All",
    "history_actor_all": "All staff",
    "history_events_all": "All events",
    "history_events_selected": "%d selected",
    "history_date_today": "Today",
    "history_date_yesterday": "Yesterday",
    "history_error": "Couldn't load history.",
    "history_action_by": "%@ %@",

    // Audit trail / history
    "history": "History",
    "show_history": "Show history",
    "hide_history": "Hide history",
    "event_created": "Created",
    "event_started": "Started",
    "event_completed": "Completed",
    "event_undone": "Undone",
    "event_reassigned": "Reassigned",
    "event_note_added": "Note added",
    "event_note_updated": "Note updated",
    "event_photo_added": "Photo added",
    "event_deleted": "Deleted",
    "task_deleted_toast": "Task deleted",
    "tasks_filter_category": "Category",
    "tasks_filter_assignee": "Assignee",
    "filter_one_off": "One-off",
    "search_tasks": "Search tasks",
    "search_staff": "Search staff",
    "search_history": "Search history",
    "staff_filter_role": "Role",
    "staff_filter_status": "Status",
    "role_all": "All",
    "role_admins": "Admins",
    "role_staff_only": "Staff",
    "status_all": "All",
    "status_active": "Active",
    "status_inactive": "Inactive",
    "by_actor": "by %@",
    "duration": "Duration",
    "started_label": "Started",
    "completed_label": "Completed",
    "no_history": "No history yet.",
]

private let jaStrings: [String: String] = [
    // Common
    "cancel": "キャンセル",
    "save": "保存",
    "done": "完了",
    "delete": "削除",
    "edit": "編集",
    "create": "作成",
    "loading": "読み込み中",
    "error": "エラー",
    "retry": "再試行",

    // Auth
    "app_subtitle": "スタッフタスクボード",
    "app_subtitle_signup": "アカウントを作成",
    "sign_in": "サインイン",
    "sign_up": "新規登録",
    "sign_out": "サインアウト",
    "sign_out_confirm": "サインアウトしますか？",
    "email": "メール",
    "password": "パスワード",
    "password_signup": "パスワード（6文字以上）",
    "your_name": "お名前",
    "create_account": "アカウント作成",
    "signup_note": "アカウントを作成すると、スタッフプロフィールが作られます。管理者が承認と権限設定を行います。",
    "check_email": "確認メールを開いてアカウントを有効化してから、サインインしてください。",

    // Tabs
    "tab_today": "今日",
    "tab_mine": "自分",
    "tab_admin": "管理",

    // Task board
    "no_tasks_today": "今日のタスクはありません。",
    "no_tasks_mine": "自分に割り当てられたタスクはありません。",
    "no_tasks": "タスクなし",
    "tasks_done_progress": "%@/%@ 完了 · %@%%",

    // Task completion
    "start": "開始",
    "complete": "完了",
    "undo": "取り消す",
    "take_photo": "写真を撮る",
    "choose_photo": "写真を選ぶ",
    "add_note": "メモを追加（任意）",
    "completion_photo": "完了写真",

    // Task categories
    "cat_opening": "オープン",
    "cat_closing": "クローズ",
    "cat_bar": "バー",
    "cat_cleaning": "清掃",
    "cat_weekly": "週次",
    "cat_other": "その他",

    // Task priority
    "priority_low": "低",
    "priority_normal": "通常",
    "priority_high": "高",

    // Profile menu
    "edit_profile": "プロフィール編集",
    "profile": "プロフィール",
    "change_photo": "写真を変更",
    "name": "名前",
    "language": "言語",

    // Admin
    "admin_overview": "概要",
    "admin_tasks": "タスク",
    "admin_staff": "スタッフ",
    "stat_total": "合計",
    "stat_done": "完了",
    "stat_open": "未完了",
    "per_staff_today": "スタッフ別・今日",
    "staff_signup_hint": "スタッフがアプリから登録すると、自動的にここに表示されます。",
    "active": "有効",
    "inactive": "停止",
    "role_admin": "管理者",
    "role_staff": "スタッフ",

    // Task editor
    "new_task": "新しいタスク",
    "edit_task": "タスク編集",
    "title_en": "タイトル（英語）",
    "title_ja": "タイトル（日本語）",
    "category": "カテゴリ",
    "priority": "優先度",
    "assign_to": "割り当て",
    "assign_anyone": "誰でも",
    "recurring": "繰り返し",
    "repeats": "頻度",
    "repeat_daily": "毎日",
    "repeat_weekly": "毎週",
    "repeat_monthly": "毎月",
    "days": "曜日",

    // Task status
    "status_pending": "未着手",
    "status_in_progress": "作業中",
    "status_completed": "完了",

    // Time buckets
    "time_now": "今",
    "time_upcoming": "これから",
    "time_anytime": "いつでも",
    "time_done": "完了",
    "time_overdue": "期限切れ",
    "target_time": "目安時間",
    "target_time_optional": "目安時間（任意）",
    "time_window_optional": "時間帯（任意）",
    "start_time": "開始",
    "end_time": "終了",
    "end_after_start": "終了時間は開始時間より後にしてください。",
    "by_prefix": "〜",
    "anytime_clear": "いつでも",
    "set_time": "時間を設定",

    // Admin hours
    "admin_hours": "営業時間",
    "hours_hint": "週の営業時間を設定します。休業日にはタスクは生成されません。",
    "weekday_mon": "月曜日",
    "weekday_tue": "火曜日",
    "weekday_wed": "水曜日",
    "weekday_thu": "木曜日",
    "weekday_fri": "金曜日",
    "weekday_sat": "土曜日",
    "weekday_sun": "日曜日",
    "closed": "休業",
    "closed_day": "この日は休業",
    "open_time": "開店",
    "close_time": "閉店",
    "close_next_day_hint": "閉店時間が開店時間より前の場合、翌日として扱われます。",
    "prep_buffer": "仕込み時間",
    "prep_buffer_hint": "開店の何時間前から営業日が始まるか（朝の仕込みタスク用）。",
    "grace_period": "延長許容時間",
    "grace_period_hint": "閉店時刻を過ぎても営業が続いた場合、この分数だけ同じ営業日として扱います。",
    "timezone": "タイムゾーン",
    "timezone_hint": "会場のローカルタイムゾーン。すべての営業日計算に使用されます。",
    "search_timezone": "タイムゾーンを検索",
    "operating_hours": "営業時間",
    "next_day_label": "翌日",
    "admin_history": "履歴",
    "history_filter_range": "期間",
    "history_filter_events": "イベント",
    "history_filter_actor": "スタッフ",
    "history_range_today": "今日",
    "history_range_7d": "7日間",
    "history_range_30d": "30日間",
    "history_range_all": "すべて",
    "history_actor_all": "全スタッフ",
    "history_events_all": "すべて",
    "history_events_selected": "%d件選択",
    "history_date_today": "今日",
    "history_date_yesterday": "昨日",
    "history_error": "履歴を読み込めませんでした。",
    "history_action_by": "%@ %@",

    // Audit trail / history
    "history": "履歴",
    "show_history": "履歴を表示",
    "hide_history": "履歴を隠す",
    "event_created": "作成",
    "event_started": "開始",
    "event_completed": "完了",
    "event_undone": "取り消し",
    "event_reassigned": "再割り当て",
    "event_note_added": "メモ追加",
    "event_note_updated": "メモ更新",
    "event_photo_added": "写真追加",
    "event_deleted": "削除",
    "task_deleted_toast": "タスクを削除しました",
    "tasks_filter_category": "カテゴリ",
    "tasks_filter_assignee": "担当者",
    "filter_one_off": "単発",
    "search_tasks": "タスクを検索",
    "search_staff": "スタッフを検索",
    "search_history": "履歴を検索",
    "staff_filter_role": "役割",
    "staff_filter_status": "ステータス",
    "role_all": "すべて",
    "role_admins": "管理者",
    "role_staff_only": "スタッフ",
    "status_all": "すべて",
    "status_active": "アクティブ",
    "status_inactive": "非アクティブ",
    "by_actor": "by %@",
    "duration": "所要時間",
    "started_label": "開始",
    "completed_label": "完了",
    "no_history": "履歴はまだありません。",
]
