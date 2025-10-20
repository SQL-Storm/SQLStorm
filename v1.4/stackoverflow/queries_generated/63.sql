-- {"query": "63.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1446} 
WITH
-- Track top users by reputation, joining several activity signals
TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.AboutMe,
    COALESCE(b.TotalBadges, 0) AS BadgeCount,
    COALESCE(v.TotalVotes, 0) AS VoteCount,
    COALESCE(p.QuestionCount, 0) AS QuestionCount,
    COALESCE(a.AnswerCount, 0) AS AnswerCount,
    COALESCE(c.CommentCount, 0) AS CommentCount
  FROM Users u
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalVotes
    FROM Votes
    WHERE UserId IS NOT NULL
    GROUP BY UserId
  ) v ON v.UserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId AS UserId, COUNT(*) AS QuestionCount
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY OwnerUserId
  ) p ON p.UserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId AS UserId, COUNT(*) AS AnswerCount
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY OwnerUserId
  ) a ON a.UserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY UserId
  ) c ON c.UserId = u.Id
  WHERE u.Reputation >= 1000
),
-- Time-windowed activity: recent interactions and post history signals
RecentActivity AS (
  SELECT
    u.Id AS UserId,
    MAX(p.CreationDate) AS LastPostDate,
    MAX(v.CreationDate) AS LastVoteDate,
    MAX(c.CreationDate) AS LastCommentDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  GROUP BY u.Id
),
-- Complex derived metrics with window functions over posts
PostMetrics AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId AS UserId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_by_user
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- questions and answers
),
-- Correlated subquery: count of related links per post with different link types
PostLinkStats AS (
  SELECT
    pl.PostId,
    COUNT(*) FILTER (WHERE lt.Name ILIKE '%Linked%') AS LinkedCount,
    COUNT(*) FILTER (WHERE lt.Name ILIKE '%Duplicate%') AS DuplicateCount
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  GROUP BY pl.PostId
),
-- Set operation: union of high-scoring posts and recent posts
HighAndRecent AS (
  (SELECT p.PostId, p.UserId, p.Score, p.ViewCount, p.CreationDate
   FROM PostMetrics p
   WHERE p.Score > 50)
  UNION ALL
  (SELECT p.PostId, p.UserId, p.Score, p.ViewCount, p.CreationDate
   FROM PostMetrics p
   JOIN RecentActivity r ON r.UserId = p.UserId
   WHERE r.LastPostDate IS NOT NULL)
),
-- Final consolidation: compute a comprehensive benchmark row per user
BenchmarkRows AS (
  SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.BadgeCount,
    tu.VoteCount,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.CommentCount,
    ra.LastPostDate,
    ma.LastVoteDate,
    cr.LastCommentDate,
    COUNT(har.PostId) AS PostVolume,
    AVG(har.Score) AS AvgPostScore,
    SUM(har.ViewCount) AS TotalViews,
    SUM(COALESCE(pls.LinkedCount,0)) AS TotalLinkedPosts,
    SUM(COALESCE(pls.DuplicateCount,0)) AS TotalDuplicateLinks
  FROM TopUsers tu
  LEFT JOIN RecentActivity ra ON ra.UserId = tu.UserId
  LEFT JOIN (
    SELECT UserId, MAX(LastPostDate) AS LastPostDate
    FROM RecentActivity
    GROUP BY UserId
  ) ma ON ma.UserId = tu.UserId
  LEFT JOIN (
    SELECT UserId, MAX(LastVoteDate) AS LastVoteDate
    FROM RecentActivity
    GROUP BY UserId
  ) cr ON cr.UserId = tu.UserId
  LEFT JOIN HighAndRecent har ON har.UserId = tu.UserId
  LEFT JOIN PostLinkStats pls ON pls.PostId = har.PostId
  GROUP BY
    tu.UserId, tu.DisplayName, tu.Reputation, tu.BadgeCount, tu.VoteCount,
    tu.QuestionCount, tu.AnswerCount, tu.CommentCount, ra.LastPostDate,
    ma.LastVoteDate, cr.LastCommentDate
)
SELECT
  br.UserId,
  br.DisplayName,
  br.Reputation,
  br.BadgeCount,
  br.VoteCount,
  br.QuestionCount,
  br.AnswerCount,
  br.CommentCount,
  br.LastPostDate,
  br.LastVoteDate,
  br.LastCommentDate,
  br.PostVolume,
  br.AvgPostScore,
  br.TotalViews,
  br.TotalLinkedPosts,
  br.TotalDuplicateLinks,
  -- Predicates and calculated expressions to stress NULL handling and arithmetic
  CASE WHEN br.TotalViews > 0 THEN (br.TotalViews * 1.0) / NULLIF(br.PostVolume,0) ELSE NULL END AS ViewsPerPost,
  COALESCE(br.AvgPostScore, 0) * CASE WHEN br.Reputation > 5000 THEN 1.5 ELSE 1.0 END AS ScoreAdjusted,
  LENGTH(COALESCE(br.DisplayName, '')) AS DisplayNameLength,
  (SELECT MAX(ExtractionDate) FROM (
     SELECT CreationDate AS ExtractionDate FROM Posts WHERE OwnerUserId = br.UserId
     UNION ALL
     SELECT CreationDate FROM Comments WHERE UserId = br.UserId
  ) x) AS LastActivityDate
FROM BenchmarkRows br
ORDER BY br.Reputation DESC, br.PostVolume DESC
LIMIT 100;