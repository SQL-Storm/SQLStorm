-- {"query": "399.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 22858} 
WITH BadgeCounts AS (
  SELECT UserId, COUNT(*) AS badge_count
  FROM Badges
  GROUP BY UserId
),
RecentActivity AS (
  SELECT OwnerUserId AS user_id, MAX(LastActivityDate) AS last_activity_date, COUNT(*) AS post_count
  FROM Posts
  GROUP BY OwnerUserId
),
UserStats AS (
  SELECT
    u.Id AS user_id,
    COALESCE(u.DisplayName, 'Unknown') AS user_display,
    COALESCE(u.Location, 'Unknown') AS location,
    u.Reputation AS reputation,
    COALESCE(bc.badge_count, 0) AS badge_count,
    COALESCE(ra.post_count, 0) AS post_count,
    ra.last_activity_date,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS upvotes_given,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rep_rank
  FROM Users u
  LEFT JOIN BadgeCounts bc ON bc.UserId = u.Id
  LEFT JOIN RecentActivity ra ON ra.user_id = u.Id
)
SELECT * FROM (
  SELECT
     user_id,
     user_display,
     'TopReputation' AS metric_name,
     (reputation::text || ' (Upvotes given: ' || COALESCE(upvotes_given, 0)::text || ')') AS metric_value,
     post_count,
     last_activity_date,
     reputation,
     location,
     badge_count,
     rep_rank
  FROM UserStats
  ORDER BY reputation DESC
  LIMIT 50
) AS A
UNION ALL
SELECT * FROM (
  SELECT
     user_id,
     user_display,
     'MostRecentActivity' AS metric_name,
     COALESCE(TO_CHAR(last_activity_date, 'YYYY-MM-DD HH24:MI:SS'), '') AS metric_value,
     post_count,
     last_activity_date,
     reputation,
     location,
     badge_count,
     rep_rank
  FROM UserStats
  ORDER BY last_activity_date DESC NULLS LAST
  LIMIT 50
) AS B
ORDER BY user_id, metric_name;