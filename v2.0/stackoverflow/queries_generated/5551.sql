-- {"query": "5551.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 839} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
),
AuthorStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.AccountId,
    COUNT(p.PostId) AS PostsCreated,
    SUM(p.Score) AS ScoreAggregate,
    MAX(p.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN RecentActivePosts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.AccountId
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS Rank
  FROM Tags t
  WHERE t.Count > 0
),
QualifiedPosts AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.OwnerUserId,
    a.DisplayName AS OwnerDisplayName,
    a.Reputation AS OwnerReputation,
    a.LastAccessDate,
    ROW_NUMBER() OVER (
      PARTITION BY rp.PostTypeId
      ORDER BY rp.Score DESC, rp.ViewCount DESC, rp.LastActivityDate DESC
    ) AS rn
  FROM RecentActivePosts rp
  LEFT JOIN Users a ON rp.OwnerUserId = a.Id
  WHERE rp.PostTypeId IN (1, 2) -- Questions and Answers
    AND rp.Score >= 0
),
CorrelatedAnalysis AS (
  SELECT
    q.PostId,
    q.Title,
    q.Tags,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.CommentCount,
    q.OwnerUserId,
    q.OwnerDisplayName,
    q.OwnerReputation,
    q.LastAccessDate,
    -- windowed distribution of scores among same-day activity
    SUM(q.Score) OVER (PARTITION BY DATE(p.CreationDate)) AS DailyScoreSum,
    AVG(q.Score) OVER (PARTITION BY DATE(p.CreationDate)) AS DailyScoreAvg,
    MAX(q.Score) OVER (PARTITION BY DATE(p.CreationDate)) AS DailyScoreMax
  FROM QualifiedPosts q
  JOIN Posts p ON q.PostId = p.Id
  WHERE q.rn = 1
),
ComplexJoin AS (
  SELECT
    c.PostId,
    c.Title,
    c.Tags,
    c.Score,
    c.ViewCount,
    c.AnswerCount,
    c.CommentCount,
    c.OwnerDisplayName,
    c.OwnerReputation,
    c.LastAccessDate,
    t.Rank AS TopTagRank
  FROM CorrelatedAnalysis c
  LEFT JOIN LATERAL (
    SELECT tt.Rank
    FROM TopTags tt
    WHERE POSITION'' IN (c.Tags) -- crude containment to simulate tag usage
    ORDER BY tt.Rank ASC
    LIMIT 1
  ) AS t ON TRUE
),
FinalOutput AS (
  SELECT
    cw.PostId,
    cw.Title,
    cw.Tags,
    cw.Score,
    cw.ViewCount,
    cw.AnswerCount,
    cw.CommentCount,
    cw.OwnerDisplayName,
    cw.OwnerReputation,
    cw.LastAccessDate,
    cw.TopTagRank,
    CASE
      WHEN cw.TopTagRank IS NULL THEN FALSE
      ELSE TRUE
    END AS IsTopTagged
  FROM ComplexJoin cw
  ORDER BY cw.Score DESC, cw.ViewCount DESC, cw.LastAccessDate DESC
  LIMIT 100
)
SELECT
  *
FROM FinalOutput;