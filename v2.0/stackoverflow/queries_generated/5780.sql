-- {"query": "5780.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 745} 
WITH
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Body,
    p.ContentLicense,
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    u.CreationDate AS UserCreation,
    u.LastAccessDate AS UserLastAccess,
    u.Location AS UserLocation,
    v.VoteCountUp,
    v.VoteCountDown,
    b.Class AS BadgeClass,
    b.Name AS BadgeName,
    bh.PostHistoryTypeId,
    bh.CreationDate AS HistoryDate,
    bh.UserId AS HistoryUserId
  FROM Posts p
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS VoteCountUp
    FROM Votes v
    JOIN VoteTypes t ON v.VoteTypeId = t.Id
    WHERE t.Id = 2
    GROUP BY PostId
  ) v ON v.PostId = p.Id
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN PostHistory bh ON bh.PostId = p.Id
  WHERE p.PostTypeId IN (1, 2) -- questions and answers
),
Filtered AS (
  SELECT
    ra.*,
    ROW_NUMBER() OVER (
      PARTITION BY ra.PostId
      ORDER BY ra.HistoryDate DESC NULLS LAST
    ) AS rn
  FROM RecentActivity ra
)
SELECT
  ra.PostId,
  ra.PostTypeId,
  ra.Title,
  ra.CreationDate,
  ra.LastActivityDate,
  ra.Tags,
  ra.Score,
  ra.ViewCount,
  ra.CommentCount,
  ra.AnswerCount,
  ra.FavoriteCount,
  ra.Body,
  ra.ContentLicense,
  ra.UserId,
  ra.UserName,
  ra.Reputation,
  ra.UserCreation,
  ra.UserLastAccess,
  ra.UserLocation,
  ra.BadgeName,
  ra.BadgeClass,
  ra.HistoryDate,
  ra.HistoryUserId,
  STRING_AGG(DISTINCT CONCAT(ut.Name, ': ', COALESCE(ut.Value, '')), ' | ') AS ActivitySummary
FROM Filtered ra
LEFT JOIN (
  SELECT 1 AS dummy, 'Vote' AS Name, CAST(1 AS varchar) AS Value
) ut ON 1=1
LEFT JOIN Votes v2 ON v2.PostId = ra.PostId
LEFT JOIN VoteTypes vt ON v2.VoteTypeId = vt.Id
GROUP BY
  ra.PostId,
  ra.PostTypeId,
  ra.Title,
  ra.CreationDate,
  ra.LastActivityDate,
  ra.Tags,
  ra.Score,
  ra.ViewCount,
  ra.CommentCount,
  ra.AnswerCount,
  ra.FavoriteCount,
  ra.Body,
  ra.ContentLicense,
  ra.UserId,
  ra.UserName,
  ra.Reputation,
  ra.UserCreation,
  ra.UserLastAccess,
  ra.UserLocation,
  ra.BadgeName,
  ra.BadgeClass,
  ra.HistoryDate,
  ra.HistoryUserId
HAVING COUNT(*) OVER (PARTITION BY ra.PostId) > 0
ORDER BY ra.LastActivityDate DESC
LIMIT 100;