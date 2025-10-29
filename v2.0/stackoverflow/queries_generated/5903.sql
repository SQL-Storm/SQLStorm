-- {"query": "5903.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 744} 
WITH RankedQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    p.LastActivityDate,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.CreationDate DESC
    ) AS rn_by_user
  FROM Posts p
  JOIN PostTypes pt ON p.PostTypeId = pt.Id
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE pt.Name = 'Question'
    AND p.ViewCount > 0
),
Engagement AS (
  SELECT
    q.QuestionId,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.Tags,
    q.OwnerUserId,
    q.OwnerName,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - q.CreationDate)) / 3600 AS hours_since_post,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.QuestionId) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.QuestionId AND v.VoteTypeId IN (2,16)) AS UpOrModeratorVotes,
    (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = q.QuestionId) AS LastVoteDate
  FROM RankedQuestions q
  WHERE q.rn_by_user = 1
),
Windowed AS (
  SELECT
    e.QuestionId,
    e.Title,
    e.CreationDate,
    e.ViewCount,
    e.Score,
    e.OwnerUserId,
    e.OwnerName,
    e.hours_since_post,
    e.CommentCount,
    e.UpOrModeratorVotes,
    e.LastVoteDate,
    SUM(e.ViewCount) OVER (ORDER BY e.CreationDate ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS WindowViewSum,
    AVG(e.Score) OVER (ORDER BY e.CreationDate ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS WindowAvgScore
  FROM Engagement e
),
CorrelatedStats AS (
  SELECT
    w.QuestionId,
    w.Title,
    w.CreationDate,
    w.ViewCount,
    w.Score,
    w.OwnerUserId,
    w.OwnerName,
    w.hours_since_post,
    w.CommentCount,
    w.UpOrModeratorVotes,
    w.LastVoteDate,
    w.WindowViewSum,
    w.WindowAvgScore,
    pp.Title AS ParentTitle,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = w.QuestionId) AS LinkCount,
    (SELECT COUNT(*) FROM Tags t JOIN Posts p2 ON t.Id = p2.Id WHERE p2.Id = w.QuestionId) AS TagCount
  FROM Windowed w
  LEFT JOIN Posts pp ON pp.Id = (SELECT a.ParentId FROM Posts a WHERE a.Id = w.QuestionId AND a.ParentId IS NOT NULL LIMIT 1)
)
SELECT
  c.QuestionId,
  c.Title,
  c.ParentTitle,
  c.CreationDate,
  c.ViewCount,
  c.Score,
  c.WindowViewSum,
  c.WindowAvgScore,
  c.CommentCount,
  c.UpOrModeratorVotes,
  c.LastVoteDate,
  c.LinkCount,
  c.TagCount,
  c.OwnerName
FROM CorrelatedStats c
ORDER BY c.WindowViewSum DESC NULLS LAST, c.CreationDate DESC
LIMIT 100;