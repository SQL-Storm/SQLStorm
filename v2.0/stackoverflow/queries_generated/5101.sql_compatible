WITH top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS PostsCreated,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCast,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesCast,
    STRING_AGG(CASE WHEN p.PostTypeId = 1 THEN p.Title ELSE NULL END, ' | ') AS QuestionTitles
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2,3)
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.LastActivityDate DESC
    ) AS rn
  FROM Posts p
  WHERE p.LastActivityDate IS NOT NULL
)
SELECT
  t.UserId,
  t.DisplayName,
  t.Reputation,
  t.PostsCreated,
  t.UpvotesCast,
  t.DownvotesCast,
  ra.PostId,
  ra.PostTypeId,
  ra.Title,
  ra.CreationDate,
  ra.LastActivityDate,
  ra.Score,
  ra.ViewCount,
  ra.Tags,
  -- Complex derived metric: activity density over last 365 days
  EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - ra.LastActivityDate)) / 86400.0 AS days_since_last_activity,
  -- Cross-filter: users who have at least 5 posts and at least 1 upvote cast
  CASE WHEN t.PostsCreated >= 5 AND t.UpvotesCast >= 1 THEN TRUE ELSE FALSE END AS qualifies
FROM top_users t
JOIN recent_activity ra
  ON ra.OwnerUserId = t.UserId
WHERE ra.rn = 1
  AND t.Reputation >= 100
ORDER BY t.Reputation DESC, t.PostsCreated DESC
LIMIT 100;