-- {"query": "7919.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1853} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.CreationDate,
        p.LastActivityDate,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as next_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) as moving_avg_score
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
        MAX(p.CreationDate) as last_post_date,
        MAX(c.CreationDate) as last_comment_date,
        MAX(b.Date) as last_badge_date
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
ComplexPostAnalysis AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.Score,
        rp.ViewCount,
        rp.Title,
        rp.Tags,
        rp.OwnerUserId,
        rp.CreationDate,
        rp.LastActivityDate,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.rn,
        rp.prev_score,
        rp.next_score,
        rp.moving_avg_score,
        CASE 
            WHEN rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'High'
            WHEN rp.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Low'
            ELSE 'Average'
        END as score_category,
        COALESCE(rp.Tags, '') as normalized_tags,
        CASE 
            WHEN rp.AnswerCount > 0 THEN (rp.CommentCount * 1.0 / rp.AnswerCount)
            ELSE NULL 
        END as comments_per_answer,
        DATEDIFF(day, rp.CreationDate, rp.LastActivityDate) as days_active,
        CASE 
            WHEN rp.Score > 1000 THEN 'Elite'
            WHEN rp.Score > 100 THEN 'Pro'
            WHEN rp.Score > 10 THEN 'Regular'
            ELSE 'Beginner'
        END as reputation_level,
        LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(rp.Tags, '<', ''), '>', ''), ' ', ''))) as clean_tags
    FROM RankedPosts rp
    WHERE rp.rn <= 5
),
TagStatistics AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) THEN 'Popular'
            WHEN t.Count < (SELECT AVG(Count) FROM Tags) THEN 'Niche'
            ELSE 'Moderate'
        END as tag_popularity,
        CASE 
            WHEN t.Count > 1000 THEN 'Trending'
            WHEN t.Count > 100 THEN 'Growing'
            ELSE 'Stable'
        END as tag_growth,
        t.IsModeratorOnly,
        t.IsRequired
    FROM Tags t
),
FinalAnalysis AS (
    SELECT 
        cpa.Id,
        cpa.PostTypeId,
        cpa.Score,
        cpa.ViewCount,
        cpa.Title,
        cpa.Tags,
        cpa.OwnerUserId,
        cpa.CreationDate,
        cpa.LastActivityDate,
        cpa.AnswerCount,
        cpa.CommentCount,
        cpa.FavoriteCount,
        cpa.rn,
        cpa.prev_score,
        cpa.next_score,
        cpa.moving_avg_score,
        cpa.score_category,
        cpa.normalized_tags,
        cpa.comments_per_answer,
        cpa.days_active,
        cpa.reputation_level,
        cpa.clean_tags,
        ua.Reputation,
        ua.DisplayName,
        ua.Views,
        ua.UpVotes,
        ua.DownVotes,
        ua.post_count,
        ua.comment_count,
        ua.badge_count,
        ua.last_post_date,
        ua.last_comment_date,
        ua.last_badge_date,
        ts.TagName,
        ts.Count as tag_count,
        ts.tag_popularity,
        ts.tag_growth,
        ts.IsModeratorOnly,
        ts.IsRequired,
        CASE 
            WHEN cpa.Score > 0 AND cpa.ViewCount > 0 THEN (cpa.Score * 1.0 / cpa.ViewCount)
            ELSE 0 
        END as score_to_view_ratio,
        CASE 
            WHEN cpa.Score > 0 AND cpa.AnswerCount > 0 THEN (cpa.Score * 1.0 / cpa.AnswerCount)
            ELSE 0 
        END as score_to_answer_ratio,
        CASE 
            WHEN cpa.Score > 0 AND cpa.CommentCount > 0 THEN (cpa.Score * 1.0 / cpa.CommentCount)
            ELSE 0 
        END as score_to_comment_ratio,
        CASE 
            WHEN cpa.Score > cpa.prev_score AND cpa.Score > cpa.moving_avg_score THEN 'Improving'
            WHEN cpa.Score < cpa.prev_score AND cpa.Score < cpa.moving_avg_score THEN 'Declining'
            ELSE 'Stable'
        END as trend_status
    FROM ComplexPostAnalysis cpa
    JOIN UserActivity ua ON cpa.OwnerUserId = ua.UserId
    LEFT JOIN TagStatistics ts ON EXISTS (
        SELECT 1 FROM unnest(string_to_array(cpa.clean_tags, '>')) as tag 
        WHERE tag = ts.TagName
    )
    WHERE cpa.Score IS NOT NULL 
      AND cpa.ViewCount IS NOT NULL
      AND cpa.Score >= 0
      AND cpa.ViewCount >= 0
)
SELECT 
    fa.Id,
    fa.PostTypeId,
    fa.Score,
    fa.ViewCount,
    fa.Title,
    fa.Tags,
    fa.OwnerUserId,
    fa.CreationDate,
    fa.LastActivityDate,
    fa.AnswerCount,
    fa.CommentCount,
    fa.FavoriteCount,
    fa.rn,
    fa.prev_score,
    fa.next_score,
    fa.moving_avg_score,
    fa.score_category,
    fa.normalized_tags,
    fa.comments_per_answer,
    fa.days_active,
    fa.reputation_level,
    fa.clean_tags,
    fa.Reputation,
    fa.DisplayName,
    fa.Views,
    fa.UpVotes,
    fa.DownVotes,
    fa.post_count,
    fa.comment_count,
    fa.badge_count,
    fa.last_post_date,
    fa.last_comment_date,
    fa.last_badge_date,
    fa.TagName,
    fa.tag_count,
    fa.tag_popularity,
    fa.tag_growth,
    fa.IsModeratorOnly,
    fa.IsRequired,
    fa.score_to_view_ratio,
    fa.score_to_answer_ratio,
    fa.score_to_comment_ratio,
    fa.trend_status,
    CASE 
        WHEN fa.score_to_view_ratio > 10 THEN 'High Engagement'
        WHEN fa.score_to_view_ratio > 5 THEN 'Medium Engagement'
        WHEN fa.score_to_view_ratio > 1 THEN 'Low Engagement'
        ELSE 'Minimal Engagement'
    END as engagement_level,
    CASE 
        WHEN fa.trend_status = 'Improving' AND fa.score_category = 'High' THEN 'Peak Performer'
        WHEN fa.trend_status = 'Declining' AND fa.score_category = 'Low' THEN 'Underperforming'
        WHEN fa.trend_status = 'Stable' THEN 'Consistent'
        ELSE 'Variable'
    END as performance_status
FROM FinalAnalysis fa
WHERE fa.Score IS NOT NULL
  AND fa.ViewCount IS NOT NULL
  AND fa.Reputation IS NOT NULL
  AND (fa.post_count > 0 OR fa.comment_count > 0 OR fa.badge_count > 0)
  AND fa.Score >= 0
  AND fa.ViewCount >= 0
ORDER BY fa.Score DESC, fa.Reputation DESC, fa.ViewCount DESC
LIMIT 1000;