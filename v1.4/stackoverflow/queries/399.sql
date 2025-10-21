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
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes_given,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rep_rank
  FROM Users u
  LEFT JOIN BadgeCounts bc ON bc.UserId = u.Id
  LEFT JOIN RecentActivity ra ON ra.user_id = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY
    u.Id,
    u.DisplayName,
    u.Location,
    u.Reputation,
    bc.badge_count,
    ra.post_count,
    ra.last_activity_date
)
SELECT * FROM (
  SELECT
     user_id,
     user_display,
     'TopReputation' AS metric_name,
     (CAST(reputation AS TEXT) || ' (Upvotes given: ' || CAST(COALESCE(upvotes_given, 0) AS TEXT) || ')') AS metric_value,
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
     COALESCE(CAST(last_activity_date AS TEXT), '') AS metric_value,
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