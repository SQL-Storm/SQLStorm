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
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
    LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as moving_avg_score,
    CASE WHEN p.Score > 100 THEN 'High' WHEN p.Score > 50 THEN 'Medium' ELSE 'Low' END as score_category,
    CASE WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 1 ELSE 0 END as has_tags,
    COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) as engagement_count
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
  SELECT 
    u.Id as UserId,
    u.Reputation,
    u.DisplayName,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate,
    DATEDIFF(day, u.CreationDate, CURRENT_TIMESTAMP) as days_since_join,
    COUNT(DISTINCT p.Id) as post_count,
    SUM(p.Score) as total_score,
    AVG(p.Score) as avg_score,
    MAX(p.CreationDate) as last_post_date,
    STRING_AGG(p.Title, '; ') as recent_titles,
    CASE WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Active' ELSE 'Regular' END as user_activity_level
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE u.Id IS NOT NULL
  GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
PostStats AS (
  SELECT 
    p.Id as PostId,
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
    COALESCE(p.AnswerCount, 0) as answer_count,
    COALESCE(p.CommentCount, 0) as comment_count,
    COALESCE(p.FavoriteCount, 0) as favorite_count,
    CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END as is_closed
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2) AND p.CreationDate >= DATEADD(month, -12, CURRENT_TIMESTAMP)
),
TagAnalysis AS (
  SELECT 
    t.Id,
    t.TagName,
    t.Count as tag_count,
    t.IsRequired,
    t.IsModeratorOnly,
    CASE WHEN t.Count > 100 THEN 'Popular' WHEN t.Count > 50 THEN 'Moderate' ELSE 'Rare' END as tag_popularity,
    CASE WHEN t.TagName LIKE '%sql%' OR t.TagName LIKE '%database%' THEN 1 ELSE 0 END as is_database_related
  FROM Tags t
),
RecentVotes AS (
  SELECT 
    v.PostId,
    v.UserId,
    v.VoteTypeId,
    v.CreationDate,
    v.BountyAmount,
    ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) as vote_rank,
    LAG(v.VoteTypeId, 1) OVER (PARTITION BY v.PostId ORDER BY v.CreationDate) as prev_vote_type,
    COUNT(*) OVER (PARTITION BY v.PostId) as total_votes
  FROM Votes v
  WHERE v.CreationDate >= DATEADD(month, -6, CURRENT_TIMESTAMP)
),
UserBadges AS (
  SELECT 
    b.UserId,
    b.Name as badge_name,
    b.Date as badge_date,
    b.Class,
    CASE WHEN b.Class = 1 THEN 'Gold' WHEN b.Class = 2 THEN 'Silver' ELSE 'Bronze' END as badge_level,
    COUNT(*) OVER (PARTITION BY b.UserId) as total_badges,
    DENSE_RANK() OVER (PARTITION BY b.UserId ORDER BY b.Date) as badge_sequence
  FROM Badges b
),
ComplexPostAnalysis AS (
  SELECT 
    rp.Id as PostId,
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
    u.DisplayName as OwnerName,
    u.Reputation,
    u.user_activity_level,
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
    END as post_trend
  FROM RankedPosts rp
  INNER JOIN Users u ON rp.OwnerUserId = u.Id
  INNER JOIN UserActivity ps ON u.Id = ps.UserId
  LEFT JOIN PostStats ps2 ON rp.Id = ps2.PostId
  LEFT JOIN TagAnalysis ta ON ps2.Tags IS NOT NULL AND ps2.Tags LIKE '%' + ta.TagName + '%'
  LEFT JOIN RecentVotes ra ON rp.Id = ra.PostId AND ra.vote_rank = 1
  LEFT JOIN UserBadges ub ON u.Id = ub.UserId AND ub.badge_sequence = 1
  WHERE rp.rn = 1
)
SELECT 
  COUNT(*) as total_posts,
  COUNT(DISTINCT PostId) as unique_posts,
  COUNT(DISTINCT OwnerName) as unique_authors,
  AVG(Score) as avg_score,
  AVG(ViewCount) as avg_views,
  AVG(AnswerCount) as avg_answers,
  AVG(CommentCount) as avg_comments,
  AVG(FavoriteCount) as avg_favorites,
  MAX(CreationDate) as latest_post_date,
  MIN(CreationDate) as earliest_post_date,
  SUM(CASE WHEN is_closed = 1 THEN 1 ELSE 0 END) as closed_posts,
  SUM(CASE WHEN has_tags = 1 THEN 1 ELSE 0 END) as tagged_posts,
  AVG(moving_avg_score) as overall_avg_moving_score,
  STRING_AGG(CONCAT_WS(' | ', PostId, Title, OwnerName, Score, ViewCount), ' | ') as post_summary,
  STRING_AGG(CONCAT_WS(',', post_trend, badge_level, Reputation, tag_popularity), ';') as detailed_attributes
FROM ComplexPostAnalysis
WHERE post_trend IN ('Trending', 'Popular', 'Noticeable')
  AND badge_level IN ('Gold', 'Silver')
  AND Reputation >= 1000
  AND tag_popularity IN ('Popular', 'Moderate')
  AND (AnswerCount > 5 OR CommentCount > 10 OR FavoriteCount > 3)
  AND (Prev_score IS NOT NULL AND Score > Prev_score * 1.5)
  AND (ABS(Score - moving_avg_score) > 10 OR moving_avg_score > 25)
  AND EXISTS (
    SELECT 1 FROM Comments c 
    WHERE c.PostId = ComplexPostAnalysis.PostId 
    AND c.CreationDate >= DATEADD(day, -30, CURRENT_TIMESTAMP)
    AND LOWER(c.Text) LIKE '%sql%'
  )
  AND NOT EXISTS (
    SELECT 1 FROM Posts p 
    WHERE p.ParentId = ComplexPostAnalysis.PostId 
    AND p.PostTypeId = 2 
    AND p.Score < 0
  )
ORDER BY Score DESC
LIMIT 1000;