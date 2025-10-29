-- {"query": "5241.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 937} 
WITH
RecentActiveQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Question
    AND p.ClosedDate IS NULL
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    CASE
      WHEN t.Count >= 1000 THEN 'Hot'
      WHEN t.Count >= 100 THEN 'Warm'
      ELSE 'New'
    END AS TagPopularity
  FROM Tags t
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COALESCE(u.Location, '') AS Location,
    -- total posts by user
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id) AS TotalPosts,
    -- total accepted answers
    (SELECT COUNT(*) FROM Posts a WHERE a.OwnerUserId = u.Id AND a.AcceptedAnswerId IS NOT NULL) AS AcceptedAnswers
  FROM Users u
),
BenchmarkSample AS (
  SELECT
    q.QuestionId,
    q.Title,
    q.CreationDate AS QuestionDate,
    q.ViewCount,
    q.Score,
    q.OwnerUserId,
    u.DisplayName AS OwnerName,
    q.Tags,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.QuestionId) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.QuestionId AND v.VoteTypeId = 2) AS UpVotesOnQuestion,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.QuestionId AND v.VoteTypeId = 3) AS DownVotesOnQuestion,
    (SELECT TOP 1 v.CreationDate FROM Votes v WHERE v.PostId = q.QuestionId AND v.VoteTypeId = 2 ORDER BY v.CreationDate DESC) AS LastUpVoteDate,
    EXISTS (
      SELECT 1 FROM PostLinks pl
      WHERE pl.PostId = q.QuestionId AND pl.RelatedPostId IN (SELECT Id FROM Posts WHERE PostTypeId = 1)
        AND pl.LinkTypeId = 1
    ) AS HasLinkedQuestion,
    (SELECT STRING_AGG(CONCAT(pl.RelatedPostId), ',') FROM PostLinks pl WHERE pl.PostId = q.QuestionId) AS LinkedQuestionIds
  FROM RecentActiveQuestions q
  LEFT JOIN Users u ON q.OwnerUserId = u.Id
  WHERE q.rn = 1
),
CorrelationFactors AS (
  SELECT
    b.QuestionId,
    b.Title,
    b.OwnerName,
    b.CommentCount,
    b.UpVotesOnQuestion,
    b.DownVotesOnQuestion,
    b.LinkedQuestionIds,
    ROW_NUMBER() OVER (ORDER BY b.CreationDate DESC, b.ViewCount DESC) AS RowOrd
  FROM BenchmarkSample b
)
SELECT
  cq.QuestionId,
  cq.Title,
  cq.OwnerName,
  cq.CreationDate AS CreatedAt,
  cq.ViewCount,
  cq.Score,
  cq.Tags,
  cq.CommentCount,
  cq.UpVotesOnQuestion,
  cq.DownVotesOnQuestion,
  cq.LinkedQuestionIds,
  t.TagPopularity,
  u.TotalPosts,
  u.AcceptedAnswers,
  (COALESCE(u.Reputation,0) * 1.0) / NULLIF((1 + cq.ViewCount), 0) AS EngagementIndex,
  CASE
    WHEN cq.CommentCount > 50 THEN 'HeavyComment'
    WHEN cq.CommentCount BETWEEN 20 AND 50 THEN 'ModerateComment'
    ELSE 'LightComment'
  END AS CommentDensity,
  CASE
    WHEN cq.UpVotesOnQuestion - cq.DownVotesOnQuestion > 5 THEN 'Positive'
    WHEN cq.UpVotesOnQuestion - cq.DownVotesOnQuestion < -5 THEN 'Negative'
    ELSE 'Neutral'
  END AS NetVoteMood
FROM CorrelationFactors cq
LEFT JOIN TopTags t ON 1=1
LEFT JOIN UserStats u ON cq.OwnerName = u.DisplayName
ORDER BY cq.RowOrd
LIMIT 100;