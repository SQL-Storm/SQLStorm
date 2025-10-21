WITH Q AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    (SELECT t.tag
     FROM unnest(string_to_array(CASE WHEN p.Tags IS NULL OR LENGTH(p.Tags) < 4 THEN '' ELSE SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) END, '><')) AS t(tag)
     ORDER BY t.tag
     LIMIT 1) AS TopTag,
    COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerName,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.LastEditDate,
    (SELECT ph.Comment FROM PostHistory ph
     WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
     ORDER BY ph.CreationDate DESC
     LIMIT 1) AS LastCloseReasonId,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id) AS RelatedLinkCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) AS LinkedCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateCount,
    (SELECT COUNT(*) FROM unnest(string_to_array(CASE WHEN p.Tags IS NULL OR LENGTH(p.Tags) < 4 THEN '' ELSE SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) END, '><')) AS t(tag) WHERE t.tag <> '') AS TagCount,
    (p.Score * 2.0) + (p.ViewCount * 0.5) + (p.AnswerCount * 3.0) + (p.CommentCount * 0.75) AS Weight
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
),
A AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    NULL AS TopTag,
    COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerName,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.LastEditDate,
    NULL AS LastCloseReasonId,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id) AS RelatedLinkCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) AS LinkedCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateCount,
    0 AS TagCount,
    (p.Score * 2.0) + (p.ViewCount * 0.5) + (p.AnswerCount * 2.5) + (p.CommentCount * 0.75) AS Weight
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 2
)
SELECT t.PostId,
       t.PostTypeId,
       t.Title,
       t.TopTag,
       t.OwnerName,
       t.OwnerReputation,
       t.CreationDate,
       t.LastActivityDate,
       t.Score,
       t.ViewCount,
       t.AnswerCount,
       t.CommentCount,
       t.FavoriteCount,
       t.LastEditDate,
       t.LastCloseReasonId,
       t.RelatedLinkCount,
       t.LinkedCount,
       t.DuplicateCount,
       t.TagCount,
       t.Weight,
       ROW_NUMBER() OVER (PARTITION BY COALESCE(t.TopTag, 'NO_TAG') ORDER BY t.Weight DESC) AS TagGroupRank
FROM (
  SELECT * FROM Q
  UNION ALL
  SELECT * FROM A
) AS t
ORDER BY t.Weight DESC
LIMIT 100;