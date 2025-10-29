-- {"query": "7535.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2396} 
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
        p.LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as total_posts,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as avg_score,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        NTH_VALUE(p.Score, 2) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as second_score
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
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT c.Id) as comment_count,
        COUNT(DISTINCT b.Id) as badge_count,
        COUNT(DISTINCT v.Id) as vote_count,
        MAX(p.CreationDate) as last_post_date,
        MAX(c.CreationDate) as last_comment_date,
        MAX(b.Date) as last_badge_date,
        MAX(v.CreationDate) as last_vote_date,
        CASE WHEN u.Reputation > 10000 THEN 'High'
             WHEN u.Reputation > 1000 THEN 'Medium'
             ELSE 'Low' END as reputation_level
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE WHEN t.Count > 100 THEN 'Popular'
             WHEN t.Count > 50 THEN 'Moderate'
             ELSE 'Rare' END as tag_popularity,
        STRING_AGG(DISTINCT p.Title, '; ') as sample_questions
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
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
        CASE WHEN p.Tags IS NULL OR p.Tags = '' THEN 'No Tags'
             ELSE 'Has Tags' END as has_tags,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) as engagement_count,
        DATEDIFF('day', p.CreationDate, CURRENT_TIMESTAMP) as age_days,
        CASE WHEN p.Score > 100 THEN 'Highly Voted'
             WHEN p.Score > 10 THEN 'Moderately Voted'
             ELSE 'Low Voted' END as vote_rating,
        CASE WHEN p.ViewCount > 1000 THEN 'Highly Viewed'
             WHEN p.ViewCount > 100 THEN 'Moderately Viewed'
             ELSE 'Low Viewed' END as view_rating,
        EXTRACT(YEAR FROM p.CreationDate) as creation_year,
        EXTRACT(MONTH FROM p.CreationDate) as creation_month,
        CASE WHEN p.LastActivityDate > DATEADD('day', -7, CURRENT_TIMESTAMP) THEN 'Recently Active'
             ELSE 'Inactive' END as activity_status
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
CombinedData AS (
    SELECT 
        rs.Id,
        rs.PostTypeId,
        rs.OwnerUserId,
        rs.Score,
        rs.ViewCount,
        rs.CreationDate,
        rs.Title,
        rs.Tags,
        rs.AnswerCount,
        rs.CommentCount,
        rs.FavoriteCount,
        rs.LastActivityDate,
        rs.rn,
        rs.total_posts,
        rs.avg_score,
        rs.prev_score,
        rs.second_score,
        ua.post_count,
        ua.comment_count,
        ua.badge_count,
        ua.vote_count,
        ua.reputation_level,
        ta.TagName,
        ta.Count,
        ta.tag_popularity,
        ps.PostId,
        ps.Score as post_score,
        ps.ViewCount as post_view_count,
        ps.AnswerCount as post_answer_count,
        ps.CommentCount as post_comment_count,
        ps.FavoriteCount as post_favorite_count,
        ps.CreationDate as post_creation_date,
        ps.has_tags,
        ps.engagement_count,
        ps.age_days,
        ps.vote_rating,
        ps.view_rating,
        ps.creation_year,
        ps.creation_month,
        ps.activity_status
    FROM RankedPosts rs
    LEFT JOIN UserActivity ua ON rs.OwnerUserId = ua.UserId
    LEFT JOIN PostStats ps ON rs.Id = ps.PostId
    LEFT JOIN TagAnalysis ta ON rs.Tags LIKE '%' || ta.TagName || '%'
    WHERE rs.rn <= 5
),
FinalAnalysis AS (
    SELECT 
        cd.Id,
        cd.PostTypeId,
        cd.OwnerUserId,
        cd.Score,
        cd.ViewCount,
        cd.CreationDate,
        cd.Title,
        cd.Tags,
        cd.AnswerCount,
        cd.CommentCount,
        cd.FavoriteCount,
        cd.LastActivityDate,
        cd.rn,
        cd.total_posts,
        cd.avg_score,
        cd.prev_score,
        cd.second_score,
        cd.post_count,
        cd.comment_count,
        cd.badge_count,
        cd.vote_count,
        cd.reputation_level,
        cd.TagName,
        cd.Count,
        cd.tag_popularity,
        cd.PostId,
        cd.post_score,
        cd.post_view_count,
        cd.post_answer_count,
        cd.post_comment_count,
        cd.post_favorite_count,
        cd.post_creation_date,
        cd.has_tags,
        cd.engagement_count,
        cd.age_days,
        cd.vote_rating,
        cd.view_rating,
        cd.creation_year,
        cd.creation_month,
        cd.activity_status,
        CASE WHEN cd.Score > cd.avg_score THEN 'Above Average'
             WHEN cd.Score < cd.avg_score THEN 'Below Average'
             ELSE 'Average' END as score_relative_to_user,
        CASE WHEN cd.total_posts > 5 THEN 'Active Poster'
             WHEN cd.total_posts > 1 THEN 'Occasional Poster'
             ELSE 'Occasional Poster' END as posting_frequency,
        CASE WHEN cd.engagement_count > 50 THEN 'High Engagement'
             WHEN cd.engagement_count > 10 THEN 'Moderate Engagement'
             ELSE 'Low Engagement' END as engagement_level,
        CASE WHEN cd.age_days > 365 THEN 'Long Standing'
             WHEN cd.age_days > 30 THEN 'Recent'
             ELSE 'New' END as user_standing,
        CASE WHEN cd.tag_popularity = 'Popular' THEN 1
             WHEN cd.tag_popularity = 'Moderate' THEN 2
             ELSE 3 END as tag_priority
    FROM CombinedData cd
)
SELECT 
    fa.Id,
    fa.PostTypeId,
    fa.OwnerUserId,
    fa.Score,
    fa.ViewCount,
    fa.CreationDate,
    fa.Title,
    fa.Tags,
    fa.AnswerCount,
    fa.CommentCount,
    fa.FavoriteCount,
    fa.LastActivityDate,
    fa.rn,
    fa.total_posts,
    fa.avg_score,
    fa.prev_score,
    fa.second_score,
    fa.post_count,
    fa.comment_count,
    fa.badge_count,
    fa.vote_count,
    fa.reputation_level,
    fa.TagName,
    fa.Count,
    fa.tag_popularity,
    fa.PostId,
    fa.post_score,
    fa.post_view_count,
    fa.post_answer_count,
    fa.post_comment_count,
    fa.post_favorite_count,
    fa.post_creation_date,
    fa.has_tags,
    fa.engagement_count,
    fa.age_days,
    fa.vote_rating,
    fa.view_rating,
    fa.creation_year,
    fa.creation_month,
    fa.activity_status,
    fa.score_relative_to_user,
    fa.posting_frequency,
    fa.engagement_level,
    fa.user_standing,
    fa.tag_priority,
    ROW_NUMBER() OVER (ORDER BY fa.Score DESC, fa.ViewCount DESC) as ranking,
    DENSE_RANK() OVER (ORDER BY fa.reputation_level, fa.post_count DESC) as user_rank,
    NTILE(4) OVER (ORDER BY fa.score_relative_to_user, fa.engagement_level) as performance_quartile,
    LAG(fa.Score, 1) OVER (ORDER BY fa.Score DESC) as next_highest_score,
    LEAD(fa.Score, 1) OVER (ORDER BY fa.Score DESC) as next_lowest_score,
    RANK() OVER (PARTITION BY fa.creation_year ORDER BY fa.Score DESC) as yearly_rank,
    PERCENT_RANK() OVER (ORDER BY fa.Score) as score_percentile,
    CUME_DIST() OVER (ORDER BY fa.engagement_count) as engagement_distribution,
    MAX(fa.Score) OVER (PARTITION BY fa.OwnerUserId) as max_score_per_user,
    MIN(fa.ViewCount) OVER (PARTITION BY fa.creation_year) as min_views_per_year,
    AVG(fa.engagement_count) OVER (PARTITION BY fa.creation_month) as avg_engagement_per_month,
    COUNT(*) OVER () as total_records,
    SUM(fa.Score) OVER (ORDER BY fa.CreationDate) as cumulative_score,
    CONCAT('Post: ', fa.Title, ' - by: ', COALESCE(u.DisplayName, 'Unknown'), ' - Tags: ', COALESCE(fa.Tags, 'None')) as post_summary,
    CASE WHEN fa.prev_score IS NOT NULL THEN (fa.Score - fa.prev_score) / NULLIF(fa.prev_score, 0) * 100
         ELSE NULL END as score_change_percent,
    CASE WHEN fa.tag_priority = 1 THEN 'High Priority Tag'
         WHEN fa.tag_priority = 2 THEN 'Medium Priority Tag'
         ELSE 'Low Priority Tag' END as priority_tag_description
FROM FinalAnalysis fa
LEFT JOIN Users u ON fa.OwnerUserId = u.Id
WHERE fa.Score IS NOT NULL 
  AND (fa.post_count > 0 OR fa.comment_count > 0)
  AND fa.creation_year >= EXTRACT(YEAR FROM DATEADD('year', -2, CURRENT_TIMESTAMP))
  AND (fa.has_tags = 'Has Tags' OR fa.TagName IS NOT NULL)
  AND (fa.activity_status = 'Recently Active' OR fa.TagName IS NOT NULL)
ORDER BY fa.Score DESC, fa.ViewCount DESC
LIMIT 1000;