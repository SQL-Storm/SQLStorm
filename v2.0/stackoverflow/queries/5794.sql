WITH recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    u.Id AS UserId,
    u.DisplayName AS UserDisplayName,
    ub.Name AS BadgeName,
    ub.Date AS BadgeDate,
    v.CreationDate AS VoteDate,
    vt.Name AS VoteType
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges ub ON ub.UserId = u.Id AND ub.Class IN (1,2,3) AND ub.Date >= p.CreationDate - INTERVAL '30 days'
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE p.LastActivityDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
),
expanded AS (
  SELECT
    ra.PostId,
    ra.PostTypeId,
    ra.Title,
    ra.Tags,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.Score,
    ra.ViewCount,
    ra.CommentCount,
    ra.AnswerCount,
    ra.FavoriteCount,
    ra.UserId,
    ra.UserDisplayName,
    ra.VoteDate,
    ra.VoteType,
    CASE
      WHEN ra.UserId IS NULL THEN CAST(false AS boolean)
      ELSE CAST(true AS boolean)
    END AS HasOwner
  FROM recent_activity ra
),
windowed AS (
  SELECT
    e.PostId,
    e.PostTypeId,
    e.Title,
    e.Tags,
    e.CreationDate,
    e.LastActivityDate,
    e.Score,
    e.ViewCount,
    e.CommentCount,
    e.AnswerCount,
    e.FavoriteCount,
    e.UserId,
    e.UserDisplayName,
    e.VoteDate,
    e.VoteType,
    e.HasOwner,
    ROW_NUMBER() OVER (
      PARTITION BY e.PostTypeId
      ORDER BY e.Score DESC, e.ViewCount DESC, e.LastActivityDate DESC
    ) AS rn_type
  FROM expanded e
),
top_per_type AS (
  SELECT
    w.PostId,
    w.PostTypeId,
    w.Title,
    w.Tags,
    w.CreationDate,
    w.LastActivityDate,
    w.Score,
    w.ViewCount,
    w.CommentCount,
    w.AnswerCount,
    w.FavoriteCount,
    w.UserId,
    w.UserDisplayName,
    w.VoteDate,
    w.VoteType,
    w.HasOwner
  FROM windowed w
  WHERE w.rn_type = 1
),
complex AS (
  SELECT
    q.PostId,
    q.Title,
    q.Tags,
    q.UserDisplayName AS CreatorName,
    q.LastActivityDate,
    q.Score,
    q.ViewCount,
    q.CommentCount,
    q.AnswerCount,
    q.FavoriteCount,
    q.HasOwner,
    (
      SELECT STRING_AGG(CAST(rp.Id AS varchar), ',')
      FROM Posts rp
      WHERE rp.Id != q.PostId
        AND rp.Tags IS NOT NULL
        AND rp.Tags LIKE '%' || split_part(q.Tags, '><', 1) || '%'
      LIMIT 3
    ) AS RelatedPostIds,
    pl.RelatedPostId AS LinkedPostId,
    q.UserId
  FROM top_per_type q
  LEFT JOIN PostLinks pl ON pl.PostId = q.PostId AND pl.LinkTypeId = 1
),
tag_metrics AS (
  SELECT
    c.PostId,
    c.Title,
    c.Tags,
    c.LastActivityDate,
    c.Score,
    c.ViewCount,
    c.CommentCount,
    c.AnswerCount,
    c.FavoriteCount,
    COALESCE(b.Name, 'NoBadge') AS TopTagBadge,
    COUNT(*) OVER (PARTITION BY c.PostId) AS cnt,
    c.LinkedPostId,
    c.RelatedPostIds,
    c.UserId
  FROM complex c
  LEFT JOIN Tags t ON t.ExcerptPostId = c.PostId
  LEFT JOIN Badges b ON b.Id = (
    SELECT MIN(bi.Id) FROM Badges bi WHERE bi.UserId = c.UserId AND bi.Class = 1
  )
)
SELECT
  tm.PostId,
  tm.Title,
  tm.Tags,
  tm.LastActivityDate,
  tm.Score,
  tm.ViewCount,
  tm.CommentCount,
  tm.AnswerCount,
  tm.FavoriteCount,
  tm.TopTagBadge,
  tm.LinkedPostId,
  tm.RelatedPostIds
FROM tag_metrics tm
ORDER BY tm.LastActivityDate DESC, tm.Score DESC
LIMIT 100;