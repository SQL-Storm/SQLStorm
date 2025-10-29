-- {"query": "7470.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1775}
WITH RankedPosts AS (
  SELECT 
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.Title,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
    LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_score,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS moving_avg_score,
    CASE WHEN p.Score > 100 THEN 'High' WHEN p.Score > 50 THEN 'Medium' ELSE 'Low' END AS score_category,
    CASE WHEN p.Tags IS NOT NULL AND p.Tags <> '' THEN 1 ELSE 0 END AS has_tags,
    COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) AS engagement_count
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
  SELECT 
    u.Id AS UserId,
    u.Reputation,
    u.DisplayName,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate,
    CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate)) / 86400 AS integer) AS days_since_join,
    COUNT(DISTINCT p.Id) AS post_count,
    SUM(p.Score) AS total_score,
    AVG(p.Score) AS avg_score,
    MAX(p.CreationDate) AS last_post_date,
    STRING_AGG(p.Title, '; ') AS recent_titles,
    CASE WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Active' ELSE 'Regular' END AS user_activity_level
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE u.Id IS NOT NULL
  GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
PostStats AS (
  SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.CreationDate,
    p.OwnerUserId,
    p.Tags,
    p.PostTypeId,
    COALESCE(p.AnswerCount, 0) AS answer_count,
    COALESCE(p.CommentCount, 0) AS comment_count,
    COALESCE(p.FavoriteCount, 0) AS favorite_count,
    CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS is_closed
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2) 
    AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '12 months')
),
TagAnalysis AS (
  SELECT 
    t.Id,
    t.TagName,
    t.Count AS tag_count,
    t.IsRequired,
    t.IsModeratorOnly,
    CASE WHEN t.Count > 100 THEN 'Popular' WHEN t.Count > 50 THEN 'Moderate' ELSE 'Rare' END AS tag_popularity,
    CASE WHEN t.TagName LIKE '%sql%' OR t.TagName LIKE '%database%' THEN 1 ELSE 0 END AS is_database_related
  FROM Tags t
),
RecentVotes AS (
  SELECT 
    v.PostId,
    v.UserId,
    v.VoteTypeId,
    v.CreationDate,
    v.BountyAmount,
    ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS vote_rank,
    LAG(v.VoteTypeId, 1) OVER (PARTITION BY v.PostId ORDER BY v.CreationDate) AS prev_vote_type,
    COUNT(*) OVER (PARTITION BY v.PostId) AS total_votes
  FROM Votes v
  WHERE v.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months')
),
UserBadges AS (
  SELECT 
    b.UserId,
    b.Name AS badge_name,
    b.Date AS badge_date,
    b.Class,
    CASE WHEN b.Class = 1 THEN 'Gold' WHEN b.Class = 2 THEN 'Silver' ELSE 'Bronze' END AS badge_level,
    COUNT(*) OVER (PARTITION BY b.UserId) AS total_badges,
    DENSE_RANK() OVER (PARTITION BY b.UserId ORDER BY b.Date) AS badge_sequence
  FROM Badges b
),
ComplexPostAnalysis AS (
  SELECT 
    rp.Id AS PostId,
    rp.Title,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.engagement_count,
    rp.score_category,
    rp.has_tags,
    rp.moving_avg_score,
    rp.prev_score,
    u.DisplayName AS OwnerName,
    u.Reputation,
    ps.user_activity_level,
    ps.total_score,
    ps.avg_score,
    ps.post_count,
    ps.last_post_date,
    ta.tag_popularity,
    ta.is_database_related,
    ra.BountyAmount,
    ra.total_votes,
    ra.vote_rank,
    ub.badge_level,
    ub.total_badges,
    CASE 
      WHEN rp.Score > 100 AND rp.ViewCount > 1000 THEN 'Trending'
      WHEN rp.Score > 50 AND rp.ViewCount > 500 THEN 'Popular'
      WHEN rp.Score > 0 AND rp.ViewCount > 100 THEN 'Noticeable'
      ELSE 'Normal'
    END AS post_trend,
    rp.CreationDate,
    ps2.is_closed
  FROM RankedPosts rp
  INNER JOIN Users u ON rp.OwnerUserId = u.Id
  INNER JOIN UserActivity ps ON u.Id = ps.UserId
  LEFT JOIN PostStats ps2 ON rp.Id = ps2.PostId
  LEFT JOIN TagAnalysis ta ON ps2.Tags IS NOT NULL AND ps2.Tags LIKE '%' || ta.TagName || '%'
  LEFT JOIN RecentVotes ra ON rp.Id = ra.PostId AND ra.vote_rank = 1
  LEFT JOIN UserBadges ub ON u.Id = ub.UserId AND ub.badge_sequence = 1
  WHERE rp.rn = 1
)
SELECT 
  COUNT(*) AS total_posts,
  COUNT(DISTINCT PostId) AS unique_posts,
  COUNT(DISTINCT OwnerName) AS unique_authors,
  AVG(Score) AS avg_score,
  AVG(ViewCount) AS avg_views,
  AVG(AnswerCount) AS avg_answers,
  AVG(CommentCount) AS avg_comments,
  AVG(FavoriteCount) AS avg_favorites,
  MAX(CreationDate) AS latest_post_date,
  MIN(CreationDate) AS earliest_post_date,
  SUM(CASE WHEN is_closed = 1 THEN 1 ELSE 0 END) AS closed_posts,
  SUM(CASE WHEN has_tags = 1 THEN 1 ELSE 0 END) AS tagged_posts,
  AVG(moving_avg_score) AS overall_avg_moving_score,
  STRING_AGG(
    (CAST(PostId AS varchar)
      || ' | '
      || COALESCE(Title, '')
      || ' | '
      || COALESCE(OwnerName, '')
      || ' | '
      || CAST(Score AS varchar)
      || ' | '
      || CAST(ViewCount AS varchar)
    ), ' | '
  ) AS post_summary,
  STRING_AGG(
    (COALESCE(post_trend, '')
      || ','
      || COALESCE(badge_level, '')
      || ','
      || CAST(Reputation AS varchar)
      || ','
      || COALESCE(tag_popularity, '')
    ), ';'
  ) AS detailed_attributes
FROM ComplexPostAnalysis
WHERE post_trend IN ('Trending', 'Popular', 'Noticeable')
  AND badge_level IN ('Gold', 'Silver')
  AND Reputation >= 1000
  AND tag_popularity IN ('Popular', 'Moderate')
  AND (AnswerCount > 5 OR CommentCount > 10 OR FavoriteCount > 3)
  AND (prev_score IS NOT NULL AND Score > prev_score * 1.5)
  AND (ABS(Score - moving_avg_score) > 10 OR moving_avg_score > 25)
  AND EXISTS (
    SELECT 1 FROM Comments c 
    WHERE c.PostId = ComplexPostAnalysis.PostId 
      AND c.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days')
      AND LOWER(c.Text) LIKE '%sql%'
  )
  AND NOT EXISTS (
    SELECT 1 FROM Posts p 
    WHERE p.ParentId = ComplexPostAnalysis.PostId 
      AND p.PostTypeId = 2 
      AND p.Score < 0
  )
GROUP BY post_trend, badge_level, Reputation, tag_popularity
ORDER BY MAX(Score) DESC
LIMIT 1000;