-- {"query": "5391.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 767} 
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
    -- Window function: days since last activity
    DATEDIFF(day, p.LastActivityDate, GETDATE()) AS DaysSinceLastActivity
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
cte_tags AS (
  SELECT
    rp.PostId,
    unnest := NULL,
    rp.Tags,
    rp.OwnerUserId
  FROM ranked_posts rp
),
complex_pred AS (
  SELECT
    rp.*,
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
    -- Lightly expand to include a window function over posts by the same owner
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
  -- Outer join to show related posts via PostLinks (Links to other posts)
  pl.RelatedPostId AS RelatedPostId,
  pl.LinkTypeId,
  lt.Name AS LinkTypeName
FROM aggregate a
LEFT JOIN PostLinks pl ON pl.PostId = a.PostId
LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
ORDER BY a.ScoreWeight DESC NULLS LAST, a.CreationDate ASC
LIMIT 100;