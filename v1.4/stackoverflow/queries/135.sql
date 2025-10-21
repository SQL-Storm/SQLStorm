-- {"query": "135.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 3000} 
WITH UserAgg AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.LastAccessDate,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
    SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.LastAccessDate
),
TopPostRank AS (
  SELECT
    p.OwnerUserId AS UserId,
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.LastActivityDate,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.Score DESC NULLS LAST, p.LastActivityDate DESC NULLS LAST
    ) AS rn
  FROM Posts p
),
UserBadgeInfo AS (
  SELECT
    b.UserId,
    MAX(b.Date) AS LastBadgeDate,
    COUNT(*) AS BadgeCount
  FROM Badges b
  GROUP BY b.UserId
)
SELECT
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.LastAccessDate,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.TotalViews,
  ua.UpVotes,
  ua.DownVotes,
  ubi.LastBadgeDate,
  ubi.BadgeCount,
  tpi.PostId AS TopPostId,
  tpi.Title AS TopPostTitle,
  tpi.Score AS TopPostScore,
  tpi.LastActivityDate AS TopPostDate
FROM UserAgg ua
LEFT JOIN Users u ON u.Id = ua.UserId
LEFT JOIN UserBadgeInfo ubi ON ubi.UserId = ua.UserId
LEFT JOIN (
  SELECT *
  FROM TopPostRank
  WHERE rn = 1
) tpi ON tpi.UserId = ua.UserId
ORDER BY ua.Reputation DESC
LIMIT 100;