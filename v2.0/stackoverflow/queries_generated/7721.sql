-- {"query": "7721.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1031} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
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
        END as score_category
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT c.Id) as comment_count,
        COUNT(DISTINCT b.Id) as badge_count,
        MAX(p.CreationDate) as last_post_date,
        SUM(p.Score) as total_score,
        AVG(p.Score) as avg_post_score,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as all_tags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.post_count,
    ua.comment_count,
    ua.badge_count,
    COALESCE(ua.last_post_date, '1900-01-01'::timestamp) as last_post_date,
    CASE 
        WHEN ua.total_score > 10000 THEN 'Elite'
        WHEN ua.total_score > 5000 THEN 'Advanced'
        WHEN ua.total_score > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END as user_level,
    ROUND(ua.avg_post_score::numeric, 2) as avg_post_score,
    COALESCE(ua.all_tags, '') as all_tags,
    COUNT(DISTINCT CASE WHEN rp.PostTypeId = 1 THEN rp.Id END) as question_count,
    COUNT(DISTINCT CASE WHEN rp.PostTypeId = 2 THEN rp.Id END) as answer_count,
    COUNT(DISTINCT CASE WHEN rp.Score > 50 THEN rp.Id END) as high_scored_count,
    COALESCE(ROUND(AVG(rp.Score) FILTER (WHERE rp.prev_score IS NOT NULL)::numeric, 2), 0) as avg_score_change,
    ROUND(AVG(rp.Score) FILTER (WHERE rp.score_category = 'High')::numeric, 2) as high_score_avg,
    STRING_AGG(DISTINCT CASE 
        WHEN rp.PostTypeId = 1 AND rp.AnswerCount > 0 THEN CONCAT(rp.Title, ' (', rp.AnswerCount, ' answers)')
        ELSE NULL 
    END, '; ') as question_with_answers,
    COUNT(DISTINCT CASE 
        WHEN rp.PostTypeId = 1 AND rp.CommentCount > 0 THEN rp.Id 
        ELSE NULL 
    END) as commented_questions,
    COUNT(DISTINCT CASE 
        WHEN rp.PostTypeId = 2 AND rp.Score > 10 THEN rp.Id 
        ELSE NULL 
    END) as high_scored_answers,
    COALESCE(STRING_AGG(DISTINCT 
        CASE 
            WHEN rp.Tags IS NOT NULL AND LENGTH(rp.Tags) > 2 
            THEN TRIM(SUBSTRING(rp.Tags, 2, LENGTH(rp.Tags)-2))
            ELSE NULL 
        END, ', '), '') as unique_tags_used
FROM UserActivity ua
LEFT JOIN RankedPosts rp ON ua.UserId = rp.OwnerUserId
WHERE ua.UserId IS NOT NULL
GROUP BY 
    ua.UserId, 
    ua.DisplayName, 
    ua.Reputation, 
    ua.post_count, 
    ua.comment_count, 
    ua.badge_count, 
    ua.last_post_date, 
    ua.total_score, 
    ua.avg_post_score, 
    ua.all_tags
HAVING 
    COUNT(DISTINCT rp.Id) > 0 
    AND COUNT(DISTINCT CASE WHEN rp.PostTypeId = 1 THEN rp.Id END) > 0
ORDER BY 
    ua.total_score DESC,
    ua.post_count DESC,
    ua.Reputation DESC
LIMIT 1000;