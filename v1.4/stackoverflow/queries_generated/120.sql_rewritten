-- {"query": "120.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1928} 
WITH
recent_posts AS (
  SELECT p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate, p.LastActivityDate, p.Title
  FROM Posts p
  WHERE p.LastActivityDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '15 days'
),
user_summary AS (
  SELECT
    u.Id AS user_id,
    u.DisplayName,
    u.Reputation,
    COUNT(rp.Id) AS recent_post_count,
    COALESCE(SUM(rp.Score), 0) AS recent_post_score
  FROM Users u
  LEFT JOIN recent_posts rp ON rp.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
edit_summary AS (
  SELECT
    ph.UserId AS user_id,
    COUNT(*) AS edits_last_30
  FROM PostHistory ph
  WHERE ph.PostId IN (SELECT Id FROM Posts WHERE LastEditDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days')
  GROUP BY ph.UserId
),
badge_summary AS (
  SELECT
    b.UserId AS user_id,
    COUNT(*) AS badge_count,
    MAX(b.Date) AS last_badge
  FROM Badges b
  GROUP BY b.UserId
),
combined AS (
  SELECT
    us.user_id,
    us.DisplayName,
    us.Reputation,
    us.recent_post_count,
    us.recent_post_score,
    COALESCE(es.edits_last_30, 0) AS edits_last_30,
    COALESCE(bs.badge_count, 0) AS badge_count,
    bs.last_badge
  FROM user_summary us
  LEFT JOIN edit_summary es ON es.user_id = us.user_id
  LEFT JOIN badge_summary bs ON bs.user_id = us.user_id
)
SELECT
  c.user_id,
  c.DisplayName,
  c.Reputation,
  c.recent_post_count,
  c.recent_post_score,
  c.edits_last_30,
  c.badge_count,
  c.last_badge
FROM combined c
ORDER BY c.Reputation DESC, c.recent_post_count DESC, c.recent_post_score DESC
LIMIT 200;