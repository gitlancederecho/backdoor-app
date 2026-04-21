-- =====================================================================
-- Optional seed data — a starter set of recurring tasks for The Backdoor.
-- Run AFTER creating at least one admin staff row.
-- =====================================================================

insert into tasks (title, title_ja, category, is_recurring, recurrence_type, priority)
values
  ('Turn on lights & music', '照明と音楽をつける', 'opening', true, 'daily', 'high'),
  ('Wipe down bar top', 'バーカウンターを拭く', 'opening', true, 'daily', 'normal'),
  ('Check ice supply', '氷の在庫確認', 'opening', true, 'daily', 'normal'),
  ('Stock glassware', 'グラスを補充', 'opening', true, 'daily', 'normal'),
  ('Restock beer fridges', 'ビール冷蔵庫の補充', 'bar', true, 'daily', 'normal'),
  ('Cut garnishes (lemon / lime)', 'ガーニッシュを切る', 'bar', true, 'daily', 'normal'),
  ('Clean toilets', 'トイレ清掃', 'cleaning', true, 'daily', 'high'),
  ('Sweep floor', '床を掃く', 'cleaning', true, 'daily', 'normal'),
  ('Take out trash', 'ゴミ出し', 'closing', true, 'daily', 'high'),
  ('Cash out register', 'レジ締め', 'closing', true, 'daily', 'high'),
  ('Lock up & set alarm', '施錠とアラーム設定', 'closing', true, 'daily', 'high'),
  ('Deep clean beer lines', 'ビールラインの洗浄', 'weekly', true, 'weekly', 'high')
on conflict do nothing;

-- For the weekly task, set recurrence_days to Monday (1):
update tasks set recurrence_days = '{1}'
where title = 'Deep clean beer lines' and (recurrence_days = '{}' or recurrence_days is null);

-- Materialize today's instances
select generate_daily_tasks(current_date);
