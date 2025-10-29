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
    CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - p.CreationDate)) / 86400 AS INTEGER) AS AgeDays,
    CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - p.LastActivityDate)) / 86400 AS INTEGER) AS LastActiveDays,
    COALESCE(a.AnswerCount, 0) AS AnswerCountFromAnswers
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT ParentId, COUNT(*) AS AnswerCount
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId
  ) a ON a.ParentId = p.Id
  WHERE p.PostTypeId = 1
),
expanded AS (
  SELECT
    r.PostId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    r.LastActivityDate,
    r.CommentCount,
    r.AnswerCount,
    r.Reputation,
    r.OwnerDisplayName,
    r.Location,
    r.AccountId,
    r.AgeDays,
    r.LastActiveDays,
    r.AnswerCountFromAnswers,
    CASE
      WHEN r.Score > 0 THEN 'positive'
      WHEN r.Score < 0 THEN 'negative'
      ELSE 'neutral'
    END AS Sentiment,
    CASE
      WHEN r.ViewCount = 0 OR r.ViewCount IS NULL THEN 0
      ELSE CAST(r.AnswerCountFromAnswers * 1.0 / NULLIF(r.ViewCount, 0) * 100.0 AS NUMERIC(10,2))
    END AS AnswerViewRate,
    CASE
      WHEN r.Tags IS NULL THEN NULL
      ELSE (
        SELECT t
        FROM (
          SELECT regexp_split_to_table(substring(r.Tags FROM 2 FOR char_length(r.Tags)-2), '><') AS t
        ) s
        ORDER BY t
        LIMIT 1
      )
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
    COALESCE(CASE WHEN t.IsModeratorOnly IS TRUE THEN 1 WHEN t.IsModeratorOnly IS FALSE THEN 0 ELSE 0 END, 0) AS IsTagModerated,
    CASE
      WHEN a.Location IS NULL OR a.Location = '' THEN 'Unknown'
      ELSE a.Location
    END AS LocationCanonical,
    CASE
      WHEN a.Reputation >= 2000 THEN 'Elite'
      WHEN a.Reputation >= 1000 THEN 'Veteran'
      ELSE 'Newbie'
    END AS ReputationTier
  FROM tag_agg a
  LEFT JOIN Tags t ON t.WikiPostId = a.PostId OR t.ExcerptPostId = a.PostId
  LEFT JOIN (SELECT 1 AS dummy) lo ON lo.dummy = 1
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
        AND v.VoteTypeId = 10
        AND v.UserId IS NULL
    )
)
SELECT
  *
FROM final
ORDER BY CreationDate DESC
LIMIT 200;