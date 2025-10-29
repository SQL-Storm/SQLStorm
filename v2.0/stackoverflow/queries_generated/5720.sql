-- {"query": "5720.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 689} 
WITH

-- 1) Top 5 users by Reputation who have at least one Bronze badge
TopUsers AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate
  FROM Users u
  WHERE u.Reputation > 1000
  ORDER BY u.Reputation DESC
  LIMIT 5
),

-- 2) For each top user, compute:
--    - total posts by type (Question/Answer)
--    - total comments on their posts
--    - average post score
--    - calendar-week activity (week of CreationDate)
UserStats AS (
  SELECT
    t.Id AS UserId,
    t.DisplayName AS UserName,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    SUM(c.Score) AS CommentScoreSum,
    AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgPostScore,
    DATE_TRUNC('week', p.CreationDate) AS WeekStart
  FROM TopUsers t
  LEFT JOIN Posts p ON p.OwnerUserId = t.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  GROUP BY t.Id, t.DisplayName
),

-- 3) Correlated subquery: latest post by each user
LatestPost AS (
  SELECT
    p.Id,
    p.OwnerUserId,
    p.Title,
    p.CreationDate
  FROM Posts p
  WHERE p.OwnerUserId IN (SELECT Id FROM TopUsers)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) = 1
),

-- 4) Windowed engagement: rank posts by score per user
Engagement AS (
  SELECT
    p.OwnerUserId,
    p.Id AS PostId,
    p.Title,
    p.Score,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST) AS ScoreRank
  FROM Posts p
  WHERE p.OwnerUserId IN (SELECT Id FROM TopUsers)
)

SELECT
  tu.Id AS UserId,
  tu.DisplayName AS UserName,
  us.QuestionCount,
  us.AnswerCount,
  us.AvgPostScore,
  us.WeekStart,
  lb.Title AS LatestPostTitle,
  lb.CreationDate AS LatestPostDate,
  e.PostId AS HighlightPostId,
  e.Title AS HighlightPostTitle,
  e.Score AS HighlightPostScore,
  e.ScoreRank AS HighlightPostRank,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = e.PostId) AS LinkedPostsCount,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = e.PostId AND v.VoteTypeId IN (2,14)) AS UpOrModVotes
FROM TopUsers tu
JOIN UserStats us ON us.UserId = tu.Id
LEFT JOIN LatestPost lb ON lb.OwnerUserId = tu.Id
LEFT JOIN Engagement e ON e.OwnerUserId = tu.Id
ORDER BY tu.Reputation DESC, tu.Id
LIMIT 100;