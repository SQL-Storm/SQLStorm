-- {"query": "174.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1590} 
WITH recent_user_activity AS (
  SELECT p.OwnerUserId AS UserId, COUNT(*) AS PostsLast30Days
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
  GROUP BY p.OwnerUserId
),
post_stats AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    p.Tags,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS AnswerCount,
    (SELECT STRING_AGG(cast(coalesce(vt.Name, ''), ', '), ', ') 
       FROM Votes v
       JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
       WHERE v.PostId = p.Id) AS VoteSummary,
    COALESCE((
      SELECT MAX(v.CreationDate)
      FROM Votes v
      WHERE v.PostId = p.Id
    ), p.CreationDate) AS LastVoteDate,
    CASE
      WHEN p.Tags IS NULL THEN ''
      ELSE array_to_string(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><'), ',')
    END AS FlattenedTags,
    (
      SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id
    ) AS RelatedCount,
    COALESCE(rd.EditCount, 0) AS EditCount,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN recent_user_activity rd ON rd.UserId = p.OwnerUserId
  LEFT JOIN LATERAL (
    SELECT COUNT(*) AS EditCount
    FROM PostHistory ph
    WHERE ph.PostId = p.Id
      AND ph.PostHistoryTypeId IN (4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 24, 31, 33, 34, 36)
  ) AS e ON TRUE
),
top_per_type AS (
  SELECT
    ps.*,
    ROW_NUMBER() OVER (PARTITION BY ps.PostTypeId ORDER BY ps.CreationDate DESC) AS rn_type
  FROM post_stats ps
)
SELECT
  tp.PostId,
  tp.Title,
  tp.PostTypeId,
  tp.CreationDate,
  tp.LastActivityDate,
  tp.Score,
  tp.ViewCount,
  tp.OwnerUserId,
  tp.OwnerDisplayName,
  tp.Tags,
  tp.CommentCount,
  tp.AnswerCount,
  tp.VoteSummary,
  tp.LastVoteDate,
  tp.FlattenedTags,
  tp.RelatedCount,
  tp.EditCount,
  tp.rn_type
FROM top_per_type tp
WHERE tp.rn_type = 1
ORDER BY tp.PostTypeId, tp.CreationDate DESC
LIMIT 200;