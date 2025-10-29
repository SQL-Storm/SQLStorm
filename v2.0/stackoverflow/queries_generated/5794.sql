-- {"query": "5794.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 862} 
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
    v.CreatedDate AS VoteDate,
    vt.Name AS VoteType
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges ub ON ub.UserId = u.Id AND ub.Class IN (1,2,3) AND ub.Date >= p.CreationDate - interval '30 days'
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE p.LastActivityDate >= now() - interval '90 days'
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
      WHEN ra.UserId IS NULL THEN false
      ELSE true
    END AS HasOwner
  FROM recent_activity ra
),
windowed AS (
  SELECT
    e.*,
    ROW_NUMBER() OVER (
      PARTITION BY PostTypeId
      ORDER BY Score DESC, ViewCount DESC, LastActivityDate DESC
    ) AS rn_type
  FROM expanded e
),
qualify AS (
  SELECT *
  FROM windowed
  WHERE rn_type = 1
),
complex AS (
  SELECT
    q.PostId,
    q.Title,
    q.Tags,
    q.CreatorName,
    q.LastActivityDate,
    q.Score,
    q.ViewCount,
    q.CommentCount,
    q.AnswerCount,
    q.FavoriteCount,
    q.HasOwner,
    -- nested correlated subquery: top 3 related posts by the same tag where the related post is not the current one
    (
      SELECT STRING_AGG(CAST(rp.Id AS varchar), ',')
      FROM Posts rp
      WHERE rp.Id != q.PostId
        AND rp.Tags IS NOT NULL
        AND rp.Tags LIKE '%' || split_part(q.Tags, '><', 1) || '%'
      LIMIT 3
    ) AS RelatedPostIds,
    -- outer join to PostLinks to fetch links of specific type
    pl.RelatedPostId AS LinkedPostId
  FROM qualify q
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
    COUNT(*) OVER (PARTITION BY c.PostId) AS cnt
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