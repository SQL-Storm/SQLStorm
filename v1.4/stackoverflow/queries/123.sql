-- {"query": "123.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1796} 
WITH
RecentActivity AS (
  SELECT p.OwnerUserId,
         p.Id AS PostId,
         p.LastActivityDate,
         p.Score
  FROM Posts p
  WHERE p.LastActivityDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
),
UserAgg AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         COUNT(ra.PostId) AS ActivityCount,
         MAX(ra.LastActivityDate) AS LastActivity
  FROM Users u
  LEFT JOIN RecentActivity ra ON ra.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
VoteAgg AS (
  SELECT v.UserId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes30
  FROM Votes v
  JOIN Posts p ON p.Id = v.PostId
  WHERE p.LastActivityDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
  GROUP BY v.UserId
),
CommentDensity AS (
  SELECT p.OwnerUserId AS UserId,
         AVG(CASE WHEN c.Id IS NULL THEN 0 ELSE 1 END) AS AvgCommentsPerPost
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  WHERE p.LastActivityDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
  GROUP BY p.OwnerUserId
),
Ranked AS (
  SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.ActivityCount,
    ua.LastActivity,
    COALESCE(va.UpVotes30, 0) AS UpVotes30,
    COALESCE(cd.AvgCommentsPerPost, 0) AS AvgCommentsPerPost,
    ROW_NUMBER() OVER (PARTITION BY ua.UserId ORDER BY ua.LastActivity DESC NULLS LAST) AS rn
  FROM UserAgg ua
  LEFT JOIN VoteAgg va ON va.UserId = ua.UserId
  LEFT JOIN CommentDensity cd ON cd.UserId = ua.UserId
)
SELECT
  r.UserId,
  r.DisplayName,
  r.Reputation,
  r.ActivityCount,
  r.LastActivity,
  r.UpVotes30,
  r.AvgCommentsPerPost,
  (SELECT COUNT(*) FROM Badges b WHERE b.UserId = r.UserId) AS BadgeCount,
  (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = r.UserId AND p.PostTypeId = 1) AS QuestionCount,
  (SELECT STRING_AGG(b.Name, ',') FROM Badges b WHERE b.UserId = r.UserId) AS BadgeNames
FROM Ranked r
WHERE r.rn = 1

UNION ALL

SELECT
  r.UserId,
  r.DisplayName,
  r.Reputation,
  r.ActivityCount,
  r.LastActivity,
  r.UpVotes30,
  r.AvgCommentsPerPost,
  (SELECT COUNT(*) FROM Badges b WHERE b.UserId = r.UserId) AS BadgeCount,
  (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = r.UserId AND p.PostTypeId = 1) AS QuestionCount,
  (SELECT STRING_AGG(b.Name, ',') FROM Badges b WHERE b.UserId = r.UserId) AS BadgeNames
FROM Ranked r
WHERE r.rn = 2
ORDER BY UpVotes30 DESC
LIMIT 50;