-- {"query": "5418.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 939} 
WITH
-- 1) compute user activity snapshot with aggregates
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
    SUM(p.Score) AS TotalPostScore,
    MAX(p.CreationDate) AS LastCreatedPost,
    MAX(p.LastActivityDate) AS LastActivityDate,
    UNIX_TIMESTAMP(MAX(p.LastActivityDate)) AS LastActivityUnix
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
-- 2) correlate with tags via tag wiki/excerpt posts and counts
TagActivity AS (
  SELECT
    u.Id AS UserId,
    t.TagName,
    COUNT(*) AS TagUsage,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsWithTag
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Tags tg ON tg.Id = p.Tags::INT -- rough mapping placeholder
  LEFT JOIN LATERAL (
      SELECT unnest(string_to_array(p.Tags, '><')) AS tagname
  ) AS v ON true
  LEFT JOIN (SELECT distinct TagName FROM Tags) AS t ON t.TagName = v.tagname
  GROUP BY u.Id, t.TagName
),
-- 3) windowed ranking of posts by score per user
UserPostRank AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Score,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS RankByScore
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
),
-- 4) recent activity cross join to demonstrate outer joins and NULL handling
RecentActivity AS (
  SELECT
    u.Id AS UserId,
    MAX(CASE WHEN v.CreationDate > NOW() - INTERVAL '30 days' THEN v.CreationDate END) AS LastVoteDate30d,
    MAX(CASE WHEN c.CreationDate > NOW() - INTERVAL '30 days' THEN c.CreationDate END) AS LastCommentDate30d,
    MAX(p.LastActivityDate) AS LastPostActivity
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id
)
SELECT
  -- 5) combine rich metrics with complex predicates and calculations
  u.Id AS UserId,
  u.DisplayName,
  COALESCE(us.QuestionCount, 0) AS QuestionCount,
  COALESCE(us.AnswerCount, 0) AS AnswerCount,
  COALESCE(us.TotalPostScore, 0) AS TotalPostScore,
  COALESCE(ra.LastVoteDate30d, TIMESTAMP '1970-01-01') AS LastVoteDate30d,
  COALESCE(ra.LastCommentDate30d, TIMESTAMP '1970-01-01') AS LastCommentDate30d,
  COALESCE(ra.LastPostActivity, TIMESTAMP '1970-01-01') AS LastPostActivity,
  -- a computed string expression combining several fields
  CONCAT_WS(' | ',
    'Rep:' || COALESCE(NULLIF(u.Reputation, NULL), 'NA'),
    'Loc:' || COALESCE(u.Location, 'Unknown'),
    'Posts:' || (COALESCE(us.QuestionCount,0) + COALESCE(us.AnswerCount,0))
  ) AS CustomDescriptor,
  -- windowed ranking vector for top 3 posts by this user
  (SELECT JSON_AGG(JSON_BUILD_OBJECT('PostId', upr.PostId, 'Title', upr.Title, 'Score', upr.Score, 'Rank', upr.RankByScore))
     FROM UserPostRank upr
     WHERE upr.OwnerUserId = u.Id
       AND upr.RankByScore <= 3) AS TopPosts
FROM Users u
LEFT JOIN UserStats us ON us.UserId = u.Id
LEFT JOIN RecentActivity ra ON ra.UserId = u.Id
ORDER BY u.Id;