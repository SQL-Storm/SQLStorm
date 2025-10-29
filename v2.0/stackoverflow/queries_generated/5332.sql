-- {"query": "5332.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 743} 
WITH
ActiveQuestions AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.LastEditorUserId,
    p.LastEditDate
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
),
QuestionScores AS (
  SELECT
    aq.PostId,
    aq.Title,
    aq.Tags,
    aq.Score AS QuestionScore,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = aq.PostId) AS AvgBounty,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = aq.PostId AND v.VoteTypeId = 2) AS Upvotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = aq.PostId AND v.VoteTypeId = 3) AS Downvotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = aq.PostId) AS CommentCount
  FROM ActiveQuestions aq
),
CorrelatedMetrics AS (
  SELECT
    qs.PostId,
    qs.Title,
    qs.Tags,
    qs.QuestionScore,
    qs.AvgBounty,
    qs.Upvotes,
    qs.Downvotes,
    qs.CommentCount,
    -- Window function to rank by a composite score
    SUM(
      CASE
        WHEN qs.QuestionScore > 0 THEN qs.QuestionScore * 1.5
        ELSE 0
      END
    ) OVER (ORDER BY qs.QuestionScore DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningScore
  FROM QuestionScores qs
),
Enriched AS (
  SELECT
    cm.PostId,
    cm.Title,
    cm.Tags,
    cm.QuestionScore,
    cm.AvgBounty,
    cm.Upvotes,
    cm.Downvotes,
    cm.CommentCount,
    cm.RunningScore,
    u.DisplayName AS OwnerName,
    u.Reputation,
    u.CreationDate AS OwnerCreationDate,
    u.LastAccessDate AS OwnerLastAccessDate,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = cm.PostId) AS LinkCount,
    (SELECT STRING_AGG(t.TagName, ',') FROM Tags t JOIN (SELECT Id FROM Posts WHERE Id = cm.PostId) p ON t.Id = p.Id WHERE t.Id IS NOT NULL) AS TagNames
  FROM CorrelatedMetrics cm
  LEFT JOIN Users u ON u.Id = (SELECT OwnerUserId FROM Posts p WHERE p.Id = cm.PostId)
)
SELECT
  e.PostId,
  e.Title,
  e.Tags,
  e.QuestionScore,
  e.AvgBounty,
  e.Upvotes,
  e.Downvotes,
  e.CommentCount,
  e.RunningScore,
  e.OwnerName,
  e.Reputation,
  e.OwnerCreationDate,
  e.OwnerLastAccessDate,
  e.LinkCount,
  e.TagNames
FROM Enriched e
WHERE e.Upvotes > 0
  AND e.Downvotes < e.Upvotes
  AND EXISTS (
    SELECT 1
    FROM Votes v
    WHERE v.PostId = e.PostId
      AND v.VoteTypeId = 2
  )
ORDER BY e.RunningScore DESC, e.QuestionScore DESC
LIMIT 100;