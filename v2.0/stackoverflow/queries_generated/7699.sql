-- {"query": "7699.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1673} 
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
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as avg_score_3posts,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as score_rank,
        NTILE(100) OVER (ORDER BY p.Score) as score_quintile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answers,
        MAX(p.Score) as max_score,
        AVG(p.Score) as avg_score,
        SUM(p.ViewCount) as total_views,
        COUNT(DISTINCT b.Id) as badge_count,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as gold_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as silver_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as bronze_badges,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) FILTER (WHERE p.Tags IS NOT NULL), ', ') as all_tags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(p1.ViewCount, 0) as excerpt_views,
        COALESCE(p2.ViewCount, 0) as wiki_views,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 500 THEN 'Moderate'
            WHEN t.Count > 100 THEN 'Quiet'
            ELSE 'Rare'
        END as tag_category,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) as popularity_rank
    FROM Tags t
    LEFT JOIN Posts p1 ON t.ExcerptPostId = p1.Id
    LEFT JOIN Posts p2 ON t.WikiPostId = p2.Id
    WHERE t.TagName IS NOT NULL
),
ComplexQueryResults AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        COALESCE(rp.prev_score, 0) as previous_score,
        COALESCE(rp.avg_score_3posts, 0) as rolling_avg_score,
        COALESCE(us.Max_Score, 0) as user_max_score,
        COALESCE(us.Avg_Score, 0) as user_avg_score,
        CASE 
            WHEN rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Avg Question'
            ELSE 'Below Avg Question'
        END as score_category,
        (rp.Score - COALESCE(rp.prev_score, 0)) as score_change,
        (rp.Score * 0.1) + (rp.ViewCount * 0.0001) + (COALESCE(rp.AnswerCount, 0) * 0.2) as performance_index,
        ta.TagName,
        ta.Count as tag_count,
        ta.tag_category,
        ta.popularity_rank,
        CASE 
            WHEN COALESCE(us.badge_count, 0) > 50 THEN 'Veteran'
            WHEN COALESCE(us.badge_count, 0) > 20 THEN 'Experienced'
            WHEN COALESCE(us.badge_count, 0) > 5 THEN 'Intermediate'
            ELSE 'Beginner'
        END as reputation_level,
        CASE 
            WHEN rp.Score > us.Max_Score THEN 1
            WHEN rp.Score > (us.Max_Score * 0.8) THEN 2
            WHEN rp.Score > (us.Max_Score * 0.6) THEN 3
            ELSE 4
        END as performance_level,
        CASE 
            WHEN rp.LastActivityDate > CURRENT_TIMESTAMP - INTERVAL '7 days' THEN 'Active'
            WHEN rp.LastActivityDate > CURRENT_TIMESTAMP - INTERVAL '30 days' THEN 'Inactive'
            ELSE 'Very Inactive'
        END as activity_status,
        CASE 
            WHEN rp.Score > (SELECT AVG(Score) FROM Posts) AND rp.ViewCount > (SELECT AVG(ViewCount) FROM Posts) THEN 'High Performing'
            ELSE 'Standard'
        END as post_quality,
        STRING_AGG(DISTINCT ta.TagName, ', ') WITHIN GROUP (ORDER BY ta.popularity_rank) as top_tags,
        STRING_AGG(DISTINCT SUBSTRING(p.Text, 1, 50) FILTER (WHERE p.Text IS NOT NULL AND LENGTH(p.Text) > 100), ' ... ') as sample_comments
    FROM RankedPosts rp
    LEFT JOIN UserStats us ON rp.OwnerUserId = us.UserId
    LEFT JOIN Tags t ON t.TagName = ANY(string_to_array(SUBSTRING(rp.Tags, 2, LENGTH(rp.Tags) - 2), '><'))
    LEFT JOIN TagAnalysis ta ON t.Id = ta.Id
    LEFT JOIN Comments p ON p.PostId = rp.Id AND p.Text IS NOT NULL
    WHERE rp.rn = 1
    GROUP BY 
        rp.Id, rp.PostTypeId, rp.OwnerUserId, rp.Score, rp.ViewCount, rp.Title, 
        rp.Tags, rp.AnswerCount, rp.CommentCount, rp.FavoriteCount, 
        rp.prev_score, rp.avg_score_3posts, us.Max_Score, us.Avg_Score, 
        ta.TagName, ta.Count, ta.tag_category, ta.popularity_rank
)
SELECT 
    Id,
    PostTypeId,
    OwnerUserId,
    Score,
    ViewCount,
    Title,
    Tags,
    AnswerCount,
    CommentCount,
    FavoriteCount,
    previous_score,
    rolling_avg_score,
    user_max_score,
    user_avg_score,
    score_category,
    score_change,
    performance_index,
    TagName,
    tag_count,
    tag_category,
    popularity_rank,
    reputation_level,
    performance_level,
    activity_status,
    post_quality,
    top_tags,
    sample_comments
FROM ComplexQueryResults
WHERE 
    (Score > 100 OR ViewCount > 1000 OR AnswerCount > 10)
    AND (TagCategory = 'Popular' OR TagCategory = 'Moderate')
    AND (activity_status = 'Active' OR activity_status = 'Inactive')
    AND reputation_level IN ('Veteran', 'Experienced')
    AND performance_level IN (1, 2)
    AND post_quality = 'High Performing'
ORDER BY Score DESC, performance_index DESC, popularity_rank ASC
LIMIT 1000;