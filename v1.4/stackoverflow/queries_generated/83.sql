-- {"query": "83.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 768} 
WITH
TopPosters AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) AS PostsCreated,
    SUM(p.Score) FILTER (WHERE p.PostTypeId = 1) AS QuestionScoreSum
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagActivity AS (
  SELECT
    t.TagName,
    COUNT(p.Id) AS QuestionsWithTag,
    AVG(p.Score) AS AvgQuestionScore,
    MAX(p.LastActivityDate) AS LastActivity
  FROM Posts p
  JOIN LATERAL unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName) ON TRUE
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
HotNots AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    ARRAY_AGG(v.VoteTypeId) AS VoteTypesOnPost
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, p.OwnerUserId
),
CrossJoinExample AS (
  SELECT
    u.Id AS UserA,
    u2.Id AS UserB,
    u.DisplayName AS UserAName,
    u2.DisplayName AS UserBName
  FROM Users u
  CROSS JOIN Users u2
  WHERE u.Id < u2.Id
),
ComplexPredicate AS (
  SELECT
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    COALESCE(p.OwnerUserId, -1) AS OwnerId
  FROM Posts p
  WHERE
    p.PostTypeId = 1
    AND (p.Score > 5 OR p.ViewCount > 1000)
    AND (p.CreationDate > NOW() - INTERVAL '3 months')
    AND (EXISTS (
      SELECT 1
      FROM Votes v
      WHERE v.PostId = p.Id
        AND v.VoteTypeId IN (2,8)
        AND v.BountyAmount IS NULL
    ) OR p.FavoriteCount > 0)
)
SELECT
  -- Row for performance benchmarking: various computed shapes
  'Benchmark' AS BenchmarkTag,
  tp.UserId,
  tp.DisplayName AS UserDisplayName,
  tp.Reputation,
  tp.PostsCreated,
  tp.QuestionScoreSum,
  ta.TagName,
  ta.QuestionsWithTag,
  ta.AvgQuestionScore,
  ho.PostId,
  ho.Title AS PostTitle,
  ho.ViewCount,
  ho.Score AS PostScore,
  ho.CreationDate AS PostCreationDate,
  ho.LastActivityDate AS PostLastActivityDate,
  ca.UserA,
  ca.UserB,
  ca.UserAName,
  ca.UserBName,
  cp.Id AS ComplexPostId,
  cp.Title AS ComplexPostTitle,
  cp.Score AS ComplexPostScore,
  cp.ViewCount AS ComplexPostViews
FROM TopPosters tp
LEFT JOIN TagActivity ta ON true
LEFT JOIN HotNots ho ON true
LEFT JOIN CrossJoinExample ca ON true
LEFT JOIN ComplexPredicate cp ON true
ORDER BY tp.Reputation DESC, ta.QuestionsWithTag DESC
LIMIT 100;