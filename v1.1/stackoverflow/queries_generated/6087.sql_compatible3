WITH RECURSIVE ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Tags,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        CASE WHEN p.OwnerUserId IS NULL THEN 1 ELSE 0 END,
        p.Score DESC,
        p.ViewCount DESC,
        p.CreationDate DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.ClosedDate IS NULL
),
top_questions AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.OwnerUserId,
    rp.LastActivityDate,
    rp.CommentCount
  FROM ranked_posts rp
  WHERE rp.PostTypeId = 1
    AND rp.rn <= 100
),
recent_activity AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate,
    q.LastActivityDate,
    q.Score,
    q.ViewCount,
    q.OwnerUserId,
    CAST('2024-10-01 12:34:56' AS TIMESTAMP) AS ref_ts,
    CAST('2024-10-01 12:34:56' AS TIMESTAMP) - q.CreationDate AS diff_ts,
    CASE
      WHEN q.LastActivityDate > q.CreationDate THEN 'updated'
      ELSE 'new'
    END AS ActivityFlag,
    q.Tags
  FROM top_questions q
),
tags_prepared AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.Score,
    ra.ViewCount,
    ra.OwnerUserId,
    REPLACE(REPLACE(COALESCE(ra.Tags, ''), '<', ''), '>', ',') AS tags_clean
  FROM recent_activity ra
),
tag_split_recursive AS (
  SELECT
    PostId,
    Title,
    CreationDate,
    LastActivityDate,
    Score,
    ViewCount,
    OwnerUserId,
    NULLIF(TRIM(SUBSTRING(tags_clean FROM 1 FOR CASE WHEN POSITION(',' IN tags_clean)=0 THEN CHAR_LENGTH(tags_clean) ELSE POSITION(',' IN tags_clean)-1 END)), '') AS TagName,
    CASE WHEN POSITION(',' IN tags_clean)=0 THEN '' ELSE SUBSTRING(tags_clean FROM POSITION(',' IN tags_clean)+1) END AS rest
  FROM tags_prepared
  UNION ALL
  SELECT
    PostId,
    Title,
    CreationDate,
    LastActivityDate,
    Score,
    ViewCount,
    OwnerUserId,
    NULLIF(TRIM(SUBSTRING(rest FROM 1 FOR CASE WHEN POSITION(',' IN rest)=0 THEN CHAR_LENGTH(rest) ELSE POSITION(',' IN rest)-1 END)), '') AS TagName,
    CASE WHEN POSITION(',' IN rest)=0 THEN '' ELSE SUBSTRING(rest FROM POSITION(',' IN rest)+1) END AS rest
  FROM tag_split_recursive
  WHERE rest <> ''
),
stats AS (
  SELECT
    ts.PostId,
    ts.Title,
    ts.TagName,
    ts.CreationDate,
    ts.LastActivityDate,
    ts.Score,
    ts.ViewCount,
    ts.OwnerUserId,
    COUNT(*) OVER (PARTITION BY ts.PostId) AS TagCount
  FROM tag_split_recursive ts
  WHERE ts.TagName IS NOT NULL
)
SELECT
  s.PostId,
  s.Title,
  s.TagName,
  s.CreationDate,
  s.LastActivityDate,
  s.Score,
  s.ViewCount,
  s.OwnerUserId,
  s.TagCount
FROM stats s
ORDER BY s.LastActivityDate DESC, s.Score DESC, s.PostId
LIMIT 100;