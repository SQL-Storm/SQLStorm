-- {"query": "5065.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1147} 
WITH ranked_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location,
    u.AccountId,
    -- window: days since creation and last activity
    DATEDIFF(day, p.CreationDate, GETDATE()) AS AgeDays,
    DATEDIFF(day, p.LastActivityDate, GETDATE()) AS LastActiveDays,
    -- aggregates over related posts (answers)
    COALESCE(a.AnswerCount, 0) AS AnswerCountFromAnswers
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT ParentId, COUNT(*) AS AnswerCount
    FROM Posts
    WHERE PostTypeId = 2 -- Answers
    GROUP BY ParentId
  ) a ON a.ParentId = p.Id
  WHERE p.PostTypeId = 1 -- Questions
),
expanded AS (
  SELECT
    r.*,
    -- derived metrics
    CASE
      WHEN r.Score > 0 THEN 'positive'
      WHEN r.Score < 0 THEN 'negative'
      ELSE 'neutral'
    END AS Sentiment,
    CASE
      WHEN r.ViewCount = 0 THEN 0
      ELSE CAST(r.AnswerCountFromAnswers * 1.0 / NULLIF(r.ViewCount, 0) * 100.0 AS decimal(10,2))
    END AS AnswerViewRate,
    -- extract a tag sample for heavy tags
    CASE
      WHEN r.Tags IS NULL THEN NULL
      ELSE
        (SELECT t.TagName
         FROM unnest(string_to_array(substring(r.Tags, 2, length(r.Tags)-2), '><')) AS t(TagName)
         ORDER BY t.TagName
         LIMIT 1)
    END AS SampleTag
  FROM ranked_questions r
),
tag_agg AS (
  SELECT
    e.PostId,
    e.Title,
    e.Tags,
    e.CreationDate,
    e.Score,
    e.ViewCount,
    e.OwnerUserId,
    e.LastActivityDate,
    e.CommentCount,
    e.AnswerCount,
    e.Reputation,
    e.OwnerDisplayName,
    e.Location,
    e.AccountId,
    e.AgeDays,
    e.LastActiveDays,
    e.AnswerCountFromAnswers,
    e.Sentiment,
    e.AnswerViewRate,
    e.SampleTag
  FROM expanded e
),
-- correlate with recent activity from PostLinks (outer join to include posts with/without links)
activity AS (
  SELECT
    t.PostId,
    t.Title,
    t.LastActivityDate,
    t.LastActiveDays,
    l.LinkTypeId,
    lt.Name AS LinkTypeName
  FROM tag_agg t
  LEFT JOIN PostLinks l ON l.PostId = t.PostId
  LEFT JOIN LinkTypes lt ON lt.Id = l.LinkTypeId
),
-- incorporate a performance-challenging filter: construct complex predicate with NULL logic
final AS (
  SELECT
    a.PostId,
    a.Title,
    a.Tags,
    a.CreationDate,
    a.Score,
    a.ViewCount,
    a.OwnerUserId,
    a.LastActivityDate,
    a.CommentCount,
    a.AnswerCount,
    a.Reputation,
    a.OwnerDisplayName,
    a.Location,
    a.AccountId,
    a.AgeDays,
    a.LastActiveDays,
    a.AnswerCountFromAnswers,
    a.Sentiment,
    a.AnswerViewRate,
    a.SampleTag,
    COALESCE(lo.IsModeratorOnly, 0) AS IsTagModerated,
    CASE
      WHEN a.Location IS NULL THEN 'Unknown'
      WHEN a.Location = '' THEN 'Unknown'
      ELSE a.Location
    END AS LocationCanonical,
    CASE
      WHEN a.Reputation >= 2000 THEN 'Elite'
      WHEN a.Reputation >= 1000 THEN 'Veteran'
      ELSE 'Newbie'
    END AS ReputationTier
  FROM tag_agg a
  LEFT JOIN Tags t ON t.WikiPostId = a.PostId OR t.ExcerptPostId = a.PostId
  LEFT JOIN (SELECT 1 AS dummy) lo ON t.IsModeratorOnly = 1
  -- complicated filter including NULL handling and correlated subqueries
  WHERE
    (a.Score > 0 OR a.Score IS NULL)
    AND (a.ViewCount > 0 OR a.ViewCount IS NULL)
    AND (
      (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.PostId AND v.VoteTypeId = 2) > 0
      OR (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.PostId AND v.VoteTypeId = 6) > 0
      OR (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.PostId) = a.CommentCount
    )
    AND NOT EXISTS (
      SELECT 1
      FROM Votes v
      WHERE v.PostId = a.PostId
        AND v.VoteTypeId = 10 -- deletion votes
        AND v.UserId IS NULL -- include NULL-safety
    )
)
SELECT
  *
FROM final
ORDER BY CreationDate DESC
LIMIT 200;