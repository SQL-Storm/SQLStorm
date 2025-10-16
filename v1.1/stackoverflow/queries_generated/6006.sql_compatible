WITH
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.LastActivityDate,
    p.ParentId,
    p.AcceptedAnswerId,
    p.PostTypeId,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
recent_comments AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCountLast30
  FROM Comments c
  JOIN Posts p ON p.Id = c.PostId
  WHERE c.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
    AND p.PostTypeId = 1
  GROUP BY c.PostId
),
top_tags AS (
  SELECT
    t.TagName,
    t.Count AS TagUsage,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
  FROM Tags t
  WHERE COALESCE(t.IsModeratorOnly, FALSE) = FALSE
),
enriched AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.Tags,
    rq.OwnerUserId,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    rq.CreationDate,
    COALESCE(rc.CommentCountLast30, 0) AS CommentsLast30,
    rq.ViewCount,
    rq.Score,
    rq.LastActivityDate,
    rq.AcceptedAnswerId,
    rq.ParentId,
    rq.LastEditorUserId,
    rq.LastEditDate,
    rq.FavoriteCount,
    STRING_AGG(tt.TagName, ',') FILTER (WHERE tt.TagName IS NOT NULL) AS TagList
  FROM recent_questions rq
  LEFT JOIN Users u ON u.Id = rq.OwnerUserId
  LEFT JOIN recent_comments rc ON rc.PostId = rq.PostId
  LEFT JOIN Posts tpost ON tpost.Id = rq.PostId
  LEFT JOIN (
    SELECT
      p.PostId,
      UNNEST(STRING_TO_ARRAY(p.Tags, '>')) AS TagName
    FROM recent_questions p
  ) AS tt ON tt.PostId = rq.PostId
  GROUP BY
    rq.PostId, rq.Title, rq.Tags, rq.OwnerUserId, u.Reputation, u.DisplayName,
    rq.CreationDate, rc.CommentCountLast30, rq.ViewCount, rq.Score, rq.LastActivityDate,
    rq.AcceptedAnswerId, rq.ParentId, rq.LastEditorUserId, rq.LastEditDate, rq.FavoriteCount
)
SELECT
  e.PostId,
  e.Title,
  e.TagList,
  e.OwnerUserId,
  e.OwnerDisplayName,
  e.Reputation,
  e.CreationDate,
  e.ViewCount AS ViewCountPlaceholder,
  e.ViewCount,
  e.Score,
  e.CommentsLast30,
  e.LastActivityDate,
  e.AcceptedAnswerId,
  e.ParentId,
  e.LastEditorUserId,
  e.LastEditDate,
  e.FavoriteCount
FROM enriched e
LEFT JOIN (SELECT 1 AS dummy) d ON TRUE
ORDER BY
  e.CreationDate DESC
LIMIT 100;