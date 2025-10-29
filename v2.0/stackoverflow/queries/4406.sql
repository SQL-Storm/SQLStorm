-- {"query": "4406.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1277}
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.CreationDate,
    p.ClosedDate,
    p.CommunityOwnedDate,
    pt.Name AS PostTypeName,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS rn_score_desc,
    DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS dr_view_count,
    AVG(CAST(p.Score AS NUMERIC)) OVER (PARTITION BY p.PostTypeId) AS avg_score_by_type,
    SUM(p.ViewCount) OVER (PARTITION BY p.PostTypeId) AS total_views_by_type,
    CASE
      WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
      WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
      ELSE 'Active'
    END AS post_status,
    CASE
      WHEN LENGTH(REPLACE(COALESCE(p.Tags, ''), '><', '')) > 2 THEN
        SUBSTRING(p.Tags FROM 2 FOR (POSITION('><' IN p.Tags) - 2))
      ELSE NULL
    END AS first_tag
  FROM Posts AS p
  JOIN PostTypes AS pt
    ON p.PostTypeId = pt.Id
  WHERE
    p.OwnerUserId IS NOT NULL
    AND p.Score > 0
), TaggedPosts AS (
  SELECT
    rp.PostId,
    rp.OwnerUserId,
    rp.PostTypeName,
    rp.rn_score_desc,
    rp.dr_view_count,
    rp.avg_score_by_type,
    rp.total_views_by_type,
    rp.post_status,
    rp.first_tag,
    COUNT(pl.RelatedPostId) AS duplicate_link_count,
    rp.Score,
    rp.FavoriteCount,
    rp.CreationDate
  FROM RankedPosts AS rp
  LEFT JOIN PostLinks AS pl
    ON rp.PostId = pl.PostId AND pl.LinkTypeId = 3
  GROUP BY
    rp.PostId,
    rp.OwnerUserId,
    rp.PostTypeName,
    rp.rn_score_desc,
    rp.dr_view_count,
    rp.avg_score_by_type,
    rp.total_views_by_type,
    rp.post_status,
    rp.first_tag,
    rp.Score,
    rp.FavoriteCount,
    rp.CreationDate
), UserPostStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) AS total_posts_by_user,
    SUM(p.Score) AS total_score_by_user,
    AVG(CAST(p.ViewCount AS NUMERIC)) AS avg_views_by_user,
    MAX(p.CreationDate) AS latest_post_date
  FROM Users AS u
  JOIN Posts AS p
    ON u.Id = p.OwnerUserId
  WHERE
    u.Id > 0
  GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation
)
SELECT
  tp.PostId,
  tp.PostTypeName,
  tp.first_tag,
  tp.rn_score_desc,
  tp.dr_view_count,
  tp.avg_score_by_type,
  tp.total_views_by_type,
  tp.post_status,
  tp.duplicate_link_count,
  ups.DisplayName AS OwnerDisplayName,
  ups.Reputation AS OwnerReputation,
  ups.total_posts_by_user,
  ups.total_score_by_user,
  ups.avg_views_by_user,
  ups.latest_post_date,
  CASE
    WHEN tp.Score IS NULL THEN 0
    ELSE tp.Score
  END AS CurrentScore,
  COALESCE(tp.FavoriteCount, 0) AS FavoriteCount,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM Comments AS c
      WHERE
        c.PostId = tp.PostId AND LENGTH(COALESCE(c.Text, '')) > 50 AND c.CreationDate > tp.CreationDate
    ) THEN 'Has Long Comment'
    ELSE 'No Long Comment'
  END AS HasLongComment,
  CASE
    WHEN CAST(ups.Reputation AS NUMERIC) / (COALESCE(ups.total_posts_by_user,0) + 1) > 100 THEN 'High Rep per Post'
    WHEN CAST(ups.Reputation AS NUMERIC) / (COALESCE(ups.total_posts_by_user,0) + 1) < 10 THEN 'Low Rep per Post'
    ELSE 'Medium Rep per Post'
  END AS ReputationPerPostRatio,
  (tp.PostTypeName || ' - ' || COALESCE(tp.first_tag, '')) AS CompositeKey
FROM TaggedPosts AS tp
LEFT JOIN UserPostStats AS ups
  ON tp.OwnerUserId = ups.UserId
WHERE
  tp.rn_score_desc <= 100
  AND tp.dr_view_count <= 50
  AND tp.duplicate_link_count < 5
  AND (
    tp.first_tag IN ('python', 'javascript', 'java', 'c#', 'sql') OR tp.PostTypeName = 'Question'
  )
ORDER BY
  tp.avg_score_by_type DESC,
  tp.total_views_by_type DESC
LIMIT 1000;