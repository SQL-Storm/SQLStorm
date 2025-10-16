-- {"query": "14025.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 60710, "output_tokens": 27153} 
Here is an elaborate SQL query that includes various constructs for performance benchmarking:

WITH cte AS (
  SELECT
    p.Id AS PostId,
    p.CreationDate,
    p.OwnerUserId,
    p.PostTypeId,
    p.AnswerCount,
    p.ViewCount,
    p.Score,
    p.Tags,
    CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
    CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS OwnerRank
  FROM Posts p
),
top_posts AS (
  SELECT
    PostId,
    CreationDate,
    OwnerUserId,
    PostTypeId,
    AnswerCount,
    ViewCount,
    Score,
    Tags,
    IsClosed,
    IsCommunityOwned,
    OwnerRank
  FROM cte
  WHERE OwnerRank <= 5
)
SELECT
  tp.PostId,
  tp.CreationDate,
  tp.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  tp.PostTypeId,
  pt.Name AS PostTypeName,
  tp.AnswerCount,
  tp.ViewCount,
  tp.Score,
  tp.Tags,
  tp.IsClosed,
  crt.Name AS CloseReason,
  tp.IsCommunityOwned,
  COALESCE(NULLIF(STRING_AGG(DISTINCT v.VoteTypeId::VARCHAR, ','), ''), 'None') AS VoteTypes,
  COALESCE(NULLIF(STRING_AGG(DISTINCT l.LinkTypeId::VARCHAR, ','), ''), 'None') AS LinkTypes,
  COALESCE(NULLIF(STRING_AGG(DISTINCT b.Class::VARCHAR, ','), ''), 'None') AS BadgeClasses
FROM top_posts tp
LEFT JOIN Users u ON tp.OwnerUserId = u.Id
LEFT JOIN PostTypes pt ON tp.PostTypeId = pt.Id
LEFT JOIN (
  SELECT PostId, STRING_AGG(DISTINCT CloseReasonTypes.Name, ', ') AS Name
  FROM PostHistory
  JOIN CloseReasonTypes ON PostHistory.Comment::int = CloseReasonTypes.Id
  WHERE PostHistoryTypeId = 10
  GROUP BY PostId
) crt ON tp.PostId = crt.PostId
LEFT JOIN Votes v ON tp.PostId = v.PostId
LEFT JOIN PostLinks l ON tp.PostId = l.PostId
LEFT JOIN Badges b ON tp.OwnerUserId = b.UserId
GROUP BY
  tp.PostId,
  tp.CreationDate,
  tp.OwnerUserId,
  u.DisplayName,
  tp.PostTypeId,
  pt.Name,
  tp.AnswerCount,
  tp.ViewCount,
  tp.Score,
  tp.Tags,
  tp.IsClosed,
  crt.Name,
  tp.IsCommunityOwned
ORDER BY tp.Score DESC
LIMIT 100;