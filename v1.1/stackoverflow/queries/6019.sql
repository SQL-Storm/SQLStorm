WITH
recent_changes AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    p.OwnerDisplayName,
    p.ParentId,
    p.AcceptedAnswerId,
    p.ContentLicense,
    ROW_NUMBER() OVER (
      PARTITION BY CAST(p.LastActivityDate AS date)
      ORDER BY p.LastActivityDate DESC
    ) AS rn_per_day
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
  WHERE
    p.PostTypeId IN (1,2)
    AND p.LastActivityDate IS NOT NULL
),
high_activity AS (
  SELECT
    pc.PostId,
    pc.Title,
    pc.Tags,
    pc.PostTypeId,
    pc.OwnerUserId,
    pc.CreationDate,
    pc.LastActivityDate,
    pc.Score,
    pc.ViewCount,
    pc.CommentCount,
    pc.AnswerCount,
    pc.FavoriteCount,
    pc.Body,
    pc.LastEditorUserId,
    pc.LastEditDate,
    pc.OwnerDisplayName,
    pc.ParentId,
    pc.AcceptedAnswerId,
    pc.ContentLicense,
    pc.rn_per_day
  FROM recent_changes pc
  WHERE pc.rn_per_day <= 5
),
complex_calc AS (
  SELECT
    h.PostId,
    h.Title,
    h.Tags,
    h.PostTypeId,
    h.OwnerUserId,
    h.CreationDate,
    h.LastActivityDate,
    h.Score,
    h.ViewCount,
    h.CommentCount,
    h.AnswerCount,
    h.FavoriteCount,
    h.Body,
    h.LastEditorUserId,
    h.LastEditDate,
    h.OwnerDisplayName,
    h.ParentId,
    h.AcceptedAnswerId,
    h.ContentLicense,
    (h.Score * 1.0) / NULLIF(h.ViewCount,0) AS score_per_view,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = h.PostId AND v.VoteTypeId = 8) AS avg_bounty_start,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = h.PostId AND v.VoteTypeId = 2) AS upvotes_from_votes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = h.PostId AND v.VoteTypeId = 3) AS downvotes_from_votes,
    LOWER(REGEXP_REPLACE(h.Title, '[^a-zA-Z0-9\\s]', '', 'g')) AS normalized_title,
    COALESCE(h.OwnerDisplayName, 'Community') AS display_name_coalesced
  FROM high_activity h
),
filtered AS (
  SELECT
    *,
    ((score_per_view > 0.5) OR (LastActivityDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days')) AS favorable
  FROM complex_calc
)
SELECT
  f.PostId,
  f.Title,
  f.Tags,
  f.PostTypeId,
  f.OwnerUserId,
  f.OwnerDisplayName,
  f.display_name_coalesced,
  f.CreationDate,
  f.LastActivityDate,
  f.Score,
  f.ViewCount,
  f.CommentCount,
  f.AnswerCount,
  f.FavoriteCount,
  f.Body,
  f.LastEditorUserId,
  f.LastEditDate,
  f.ParentId,
  f.AcceptedAnswerId,
  f.ContentLicense,
  f.score_per_view,
  f.avg_bounty_start,
  f.upvotes_from_votes,
  f.downvotes_from_votes,
  f.normalized_title,
  f.favorable,
  t.TagName AS Tag,
  tc.Count AS TagCount
FROM filtered f
LEFT JOIN Tags t ON t.Id = (
  SELECT Id FROM Tags
  WHERE TagName = ANY (STRING_TO_ARRAY(REPLACE(REPLACE(f.Tags, '<', ''), '>', ''), ','))
  LIMIT 1
)
LEFT JOIN Posts pt ON pt.Id = t.WikiPostId
LEFT JOIN Tags tc ON tc.Id = t.Id
GROUP BY
  f.PostId, f.Title, f.Tags, f.PostTypeId, f.OwnerUserId, f.OwnerDisplayName, f.display_name_coalesced,
  f.CreationDate, f.LastActivityDate, f.Score, f.ViewCount, f.CommentCount, f.AnswerCount, f.FavoriteCount,
  f.Body, f.LastEditorUserId, f.LastEditDate, f.ParentId, f.AcceptedAnswerId, f.ContentLicense,
  f.score_per_view, f.avg_bounty_start, f.upvotes_from_votes, f.downvotes_from_votes, f.normalized_title, f.favorable,
  t.TagName, tc.Count
ORDER BY f.LastActivityDate DESC, f.Score DESC
LIMIT 100;