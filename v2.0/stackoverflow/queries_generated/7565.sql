-- {"query": "7565.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1799} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        LAG(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_views,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as avg_score_3posts,
        SUM(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as cumulative_views
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.DisplayName,
        COUNT(DISTINCT p.Id) as total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as total_questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as total_answers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as total_question_score,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as total_answer_score,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) as avg_question_score,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) as avg_answer_score,
        MAX(p.CreationDate) as latest_post_date,
        MIN(p.CreationDate) as earliest_post_date,
        DATEDIFF(day, MIN(p.CreationDate), MAX(p.CreationDate)) as active_days
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.DisplayName
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(p.ViewCount, 0) as wiki_views,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END as tag_popularity,
        CASE 
            WHEN t.IsRequired = 1 THEN 'Required'
            WHEN t.IsModeratorOnly = 1 THEN 'Moderator Only'
            ELSE 'Regular'
        END as tag_type
    FROM Tags t
    LEFT JOIN Posts p ON t.WikiPostId = p.Id
),
PostActivity AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.UserId,
        ph.CreationDate,
        ph.Comment,
        ph.Text,
        ph.RevisionGUID,
        CASE 
            WHEN ph.PostHistoryTypeId IN (1, 4, 6) THEN 'Title/Tag Edit'
            WHEN ph.PostHistoryTypeId IN (2, 5) THEN 'Body Edit'
            WHEN ph.PostHistoryTypeId IN (10, 11) THEN 'Close/Reopen'
            WHEN ph.PostHistoryTypeId = 12 THEN 'Deletion'
            WHEN ph.PostHistoryTypeId = 13 THEN 'Undeletion'
            ELSE 'Other'
        END as activity_type,
        CASE 
            WHEN ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL THEN 
                COALESCE((SELECT Name FROM CloseReasonTypes WHERE Id = CAST(ph.Comment AS INT)), 'Unknown Reason')
            ELSE 'N/A'
        END as close_reason
    FROM PostHistory ph
    WHERE ph.CreationDate >= '2020-01-01'
),
UserBadges AS (
    SELECT 
        b.UserId,
        b.Name as badge_name,
        b.Date as badge_date,
        b.Class,
        CASE 
            WHEN b.Class = 1 THEN 'Gold'
            WHEN b.Class = 2 THEN 'Silver'
            ELSE 'Bronze'
        END as badge_level,
        ROW_NUMBER() OVER (PARTITION BY b.UserId, b.Name ORDER BY b.Date DESC) as badge_rank,
        COUNT(*) OVER (PARTITION BY b.UserId) as total_badges
    FROM Badges b
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.total_posts,
    us.total_questions,
    us.total_answers,
    us.avg_question_score,
    us.avg_answer_score,
    us.total_question_score,
    us.total_answer_score,
    us.active_days,
    CASE 
        WHEN us.total_posts > 0 THEN (us.total_answer_score * 100.0 / NULLIF(us.total_question_score, 0))
        ELSE 0 
    END as answer_score_ratio,
    CASE 
        WHEN rs.Id IS NOT NULL THEN 
            CASE 
                WHEN rs.Score > rs.prev_score THEN 'Increasing'
                WHEN rs.Score < rs.prev_score THEN 'Decreasing'
                ELSE 'Stable'
            END
        ELSE 'No Recent Activity'
    END as score_trend,
    CASE 
        WHEN rs.Id IS NOT NULL AND rs.avg_score_3posts > 5 THEN 'High Performer'
        WHEN rs.Id IS NOT NULL AND rs.avg_score_3posts > 1 THEN 'Moderate Performer'
        ELSE 'Low Performer'
    END as performance_level,
    CASE 
        WHEN rs.Id IS NOT NULL AND rs.cumulative_views > 1000 THEN 'High Visibility'
        WHEN rs.Id IS NOT NULL AND rs.cumulative_views > 500 THEN 'Moderate Visibility'
        ELSE 'Low Visibility'
    END as visibility_level,
    STRING_AGG(DISTINCT ta.TagName, ', ') as associated_tags,
    STRING_AGG(DISTINCT ub.badge_name, ', ') as achievements,
    COUNT(pa.PostId) as recent_activities,
    STRING_AGG(DISTINCT pa.activity_type, ', ') as activity_types,
    STRING_AGG(DISTINCT pa.close_reason, ', ') as close_reasons,
    CASE 
        WHEN ub.badge_level = 'Gold' THEN 'Premium User'
        WHEN ub.badge_level = 'Silver' THEN 'Verified User'
        ELSE 'Regular User'
    END as user_status
FROM UserStats us
LEFT JOIN RankedPosts rs ON us.UserId = rs.OwnerUserId AND rs.rn = 1
LEFT JOIN UserBadges ub ON us.UserId = ub.UserId AND ub.badge_rank = 1
LEFT JOIN PostActivity pa ON us.UserId = pa.UserId
LEFT JOIN (
    SELECT DISTINCT 
        p.OwnerUserId,
        t.TagName
    FROM Posts p
    JOIN LATERAL (
        SELECT UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) as TagName
    ) AS tag ON tag.TagName IS NOT NULL
    JOIN Tags t ON t.TagName = tag.TagName
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
) ta ON ta.OwnerUserId = us.UserId
WHERE us.total_posts > 0
GROUP BY 
    us.UserId, 
    us.DisplayName, 
    us.Reputation, 
    us.total_posts, 
    us.total_questions, 
    us.total_answers, 
    us.avg_question_score, 
    us.avg_answer_score, 
    us.total_question_score, 
    us.total_answer_score, 
    us.active_days,
    rs.Id, 
    rs.Score, 
    rs.prev_score, 
    rs.avg_score_3posts, 
    rs.cumulative_views,
    ub.badge_level,
    CASE 
        WHEN ub.badge_level = 'Gold' THEN 'Premium User'
        WHEN ub.badge_level = 'Silver' THEN 'Verified User'
        ELSE 'Regular User'
    END
HAVING 
    COUNT(pa.PostId) > 0 
    OR EXISTS (SELECT 1 FROM UserBadges ub2 WHERE ub2.UserId = us.UserId)
    OR us.total_posts > 10
ORDER BY 
    us.Reputation DESC,
    us.total_question_score DESC,
    us.total_answer_score DESC;