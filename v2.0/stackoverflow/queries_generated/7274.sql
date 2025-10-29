-- {"query": "7274.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1987} 
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
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as avg_score,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END as score_category,
        COALESCE(p.Title, '') as clean_title
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= '2010-01-01'
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT c.Id) as comment_count,
        COUNT(DISTINCT b.Id) as badge_count,
        MAX(p.CreationDate) as last_post_date,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 1000 THEN 'Expert'
            WHEN u.Reputation > 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END as reputation_level,
        ROUND(
            CAST(COALESCE(SUM(p.Score), 0) AS FLOAT) / NULLIF(COUNT(p.Id), 0), 2
        ) as avg_post_score
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2008-01-01'
    GROUP BY u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.Views
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Rare'
        END as popularity_level,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as related_posts,
        COALESCE(
            (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%'), 
            0
        ) as avg_tag_score
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),
PostActivity AS (
    SELECT 
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.Comment,
        ph.Text,
        CASE 
            WHEN ph.PostHistoryTypeId IN (1, 4, 6) THEN 'Title/Tag Edit'
            WHEN ph.PostHistoryTypeId IN (2, 5) THEN 'Body Edit'
            WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN 'Status Change'
            ELSE 'Other'
        END as activity_type,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as latest_activity,
        DATEDIFF('DAY', ph.CreationDate, CURRENT_TIMESTAMP) as days_since_activity
    FROM PostHistory ph
    WHERE ph.CreationDate >= '2015-01-01'
),
CombinedData AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.score_category,
        rp.prev_score,
        rp.avg_score,
        us.Reputation,
        us.UpVotes,
        us.DownVotes,
        us.post_count,
        us.comment_count,
        us.badge_count,
        us.last_post_date,
        us.reputation_level,
        us.avg_post_score,
        ta.TagName,
        ta.Count as tag_count,
        ta.popularity_level,
        ta.related_posts,
        ta.avg_tag_score,
        pa.activity_type,
        pa.days_since_activity,
        CASE 
            WHEN rp.Score > 0 AND rp.AnswerCount > 0 THEN 
                ROUND(CAST(rp.AnswerCount AS FLOAT) / NULLIF(rp.Score, 0), 2)
            ELSE 0
        END as answers_per_score,
        CASE 
            WHEN rp.CommentCount > 0 AND rp.ViewCount > 0 THEN 
                ROUND(CAST(rp.CommentCount AS FLOAT) / NULLIF(rp.ViewCount, 0), 4)
            ELSE 0
        END as comments_per_view,
        CASE 
            WHEN rp.FavoriteCount > 0 AND rp.Score > 0 THEN 
                ROUND(CAST(rp.FavoriteCount AS FLOAT) / NULLIF(rp.Score, 0), 3)
            ELSE 0
        END as favorites_per_score
    FROM RankedPosts rp
    LEFT JOIN UserStats us ON rp.OwnerUserId = us.UserId
    LEFT JOIN (
        SELECT DISTINCT 
            p.Id,
            t.TagName,
            t.Count,
            t.Popularity_level,
            t.Related_posts,
            t.Avg_tag_score
        FROM Posts p
        JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
        WHERE t.TagName IS NOT NULL
    ) ta ON rp.Id = ta.Id
    LEFT JOIN PostActivity pa ON rp.Id = pa.PostId
    WHERE rp.rn = 1 
      AND us.post_count > 0
),
FinalQuery AS (
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
        cd.score_category,
        cd.prev_score,
        cd.avg_score,
        cd.Reputation,
        cd.UpVotes,
        cd.DownVotes,
        cd.post_count,
        cd.comment_count,
        cd.badge_count,
        cd.last_post_date,
        cd.reputation_level,
        cd.avg_post_score,
        cd.TagName,
        cd.tag_count,
        cd.popularity_level,
        cd.related_posts,
        cd.avg_tag_score,
        cd.activity_type,
        cd.days_since_activity,
        cd.answers_per_score,
        cd.comments_per_view,
        cd.favorites_per_score,
        CASE 
            WHEN cd.score_category = 'High' AND cd.reputation_level = 'Elite' THEN 'High Impact'
            WHEN cd.score_category = 'Medium' AND cd.reputation_level IN ('Expert', 'Elite') THEN 'Medium Impact'
            WHEN cd.score_category = 'Low' AND cd.avg_post_score > 10 THEN 'Low Score High Activity'
            ELSE 'Normal'
        END as impact_category,
        DENSE_RANK() OVER (ORDER BY cd.ViewCount DESC) as view_rank,
        RANK() OVER (ORDER BY cd.Score DESC) as score_rank,
        PERCENT_RANK() OVER (ORDER BY cd.Reputation) as reputation_percentile,
        NTILE(4) OVER (ORDER BY cd.Score) as score_quartile,
        LAG(cd.Score) OVER (ORDER BY cd.CreationDate) as prev_score_by_date,
        LAG(cd.Reputation) OVER (ORDER BY cd.CreationDate) as prev_rep_by_date
    FROM CombinedData cd
    WHERE cd.post_count > 1 
      AND cd.Reputation > 500
)
SELECT 
    f.*,
    CASE 
        WHEN f.favorites_per_score > 0.1 THEN 'Highly Favorited'
        WHEN f.answers_per_score > 0.5 THEN 'Well Answered'
        WHEN f.comments_per_view > 0.05 THEN 'Highly Commented'
        ELSE 'Regular Post'
    END as engagement_level,
    CONCAT(
        f.Title, 
        ' - Tags: ', 
        COALESCE(f.Tags, 'None'),
        ' - Score: ', 
        CAST(f.Score AS VARCHAR),
        ' - Views: ', 
        CAST(f.ViewCount AS VARCHAR)
    ) as formatted_post_info,
    ABS(f.Score - f.avg_score) as score_deviation_from_user_avg,
    CASE 
        WHEN f.days_since_activity IS NULL THEN 'Never'
        WHEN f.days_since_activity = 0 THEN 'Today'
        WHEN f.days_since_activity = 1 THEN 'Yesterday'
        ELSE CAST(f.days_since_activity AS VARCHAR) || ' days ago'
    END as activity_status
FROM FinalQuery f
WHERE f.Score > 0 
  AND f.ViewCount > 10
  AND (f.TagName IS NOT NULL OR f.Tags IS NOT NULL)
  AND f.reputation_level IN ('Elite', 'Expert')
ORDER BY f.ViewCount DESC, f.Score DESC, f.CreationDate DESC
LIMIT 1000;