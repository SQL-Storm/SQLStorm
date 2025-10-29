WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.ContentLicense,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS OwnerCreationDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.LastAccessDate,
    u.ProfileImageUrl,
    -- Window function: days since last activity (ANSI: use DATE_PART for portability where supported)
    CAST(EXTRACT(epoch FROM (TIMESTAMP '2024-10-01 12:34:56' - p.LastActivityDate)) / 86400 AS INTEGER) AS DaysSinceLastActivity
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
cte_tags AS (
  SELECT
    rp.PostId,
    NULL AS unnest,
    rp.Tags,
    rp.OwnerUserId
  FROM ranked_posts rp
),
complex_pred AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.OwnerUserId,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.LastActivityDate,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.Body,
    rp.ContentLicense,
    rp.OwnerDisplayName,
    rp.OwnerCreationDate,
    rp.Location,
    rp.Reputation,
    rp.DaysSinceLastActivity,
    -- Correlated subquery: count of comments on the post
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId) AS CommentCountSubQ,
    -- Subquery in SELECT: number of related posts via PostLinks (Linked or Duplicate)
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rp.PostId OR pl.RelatedPostId = rp.PostId) AS LinkCount,
    -- Compute a weighted score using external constants
    (rp.Score * 1.0 + COALESCE(rp.ViewCount,0) * 0.01) AS ScoreWeight
  FROM ranked_posts rp
),
aggregate AS (
  SELECT
    cp.PostId,
    cp.Title,
    cp.OwnerDisplayName,
    cp.OwnerUserId,
    cp.CreationDate,
    cp.LastActivityDate,
    cp.Score,
    cp.ViewCount,
    cp.Tags,
    cp.CommentCount,
    cp.FavoriteCount,
    cp.Body,
    cp.ContentLicense,
    cp.OwnerCreationDate,
    cp.Location,
    cp.Reputation,
    cp.DaysSinceLastActivity,
    cp.CommentCountSubQ,
    cp.LinkCount,
    cp.ScoreWeight,
    -- Window function over posts by the same owner
    SUM(cp.Score) OVER (PARTITION BY cp.OwnerUserId ORDER BY cp.CreationDate ROWS BETWEEN 100 PRECEDING AND CURRENT ROW) AS RunningOwnerScore
  FROM complex_pred cp
)
SELECT
  a.PostId,
  a.Title,
  a.OwnerDisplayName,
  a.OwnerUserId,
  a.CreationDate,
  a.LastActivityDate,
  a.Score,
  a.ViewCount,
  a.Tags,
  a.CommentCount,
  a.FavoriteCount,
  a.Body,
  a.ContentLicense,
  a.OwnerCreationDate,
  a.Location,
  a.Reputation,
  a.DaysSinceLastActivity,
  a.CommentCountSubQ,
  a.LinkCount,
  a.ScoreWeight,
  a.RunningOwnerScore,
  pl.RelatedPostId AS RelatedPostId,
  pl.LinkTypeId,
  lt.Name AS LinkTypeName
FROM aggregate a
LEFT JOIN PostLinks pl ON pl.PostId = a.PostId
LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
ORDER BY a.ScoreWeight DESC, a.CreationDate ASC
LIMIT 100;