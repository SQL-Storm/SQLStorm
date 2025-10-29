-- {"query": "7804.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1447} 
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
        p.LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END as score_category,
        COALESCE(p.Tags, '') as cleaned_tags,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags LIKE '%<%' THEN 
                STRING_AGG(SUBSTRING(p.Tags, POSITION('<' IN p.Tags) + 1, POSITION('>' IN p.Tags) - POSITION('<' IN p.Tags) - 1), ', ')
            ELSE NULL 
        END as extracted_tags,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) as days_since_creation
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= '2020-01-01'
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT p.Id) as total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answer_count,
        AVG(p.Score) as avg_score,
        MAX(p.Score) as max_score,
        MIN(p.Score) as min_score,
        SUM(p.ViewCount) as total_views,
        COALESCE(SUM(p.FavoriteCount), 0) as total_favorites,
        COUNT(DISTINCT b.Id) as badge_count,
        STRING_AGG(DISTINCT b.Name, ', ') as badge_names
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2019-01-01'
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 500 THEN 'Moderate'
            ELSE 'Rare'
        END as popularity_level,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as related_posts
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND t.Count > 0
),
ComplexAnalysis AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.OwnerUserId,
        rp.Title,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.score_category,
        rp.days_since_creation,
        rp.prev_score,
        CASE 
            WHEN rp.prev_score IS NOT NULL AND rp.Score > rp.prev_score THEN 
                (rp.Score - rp.prev_score) * 100.0 / NULLIF(rp.prev_score, 0)
            ELSE 0 
        END as score_increase_percent,
        us.Reputation,
        us.DisplayName,
        us.total_posts,
        us.question_count,
        us.answer_count,
        us.avg_score,
        us.total_views,
        us.total_favorites,
        ta.TagName,
        ta.Count,
        ta.popularity_level,
        CASE 
            WHEN us.total_posts > 100 AND us.avg_score > 10 THEN 'Active High Performer'
            WHEN us.total_posts > 50 AND us.avg_score > 5 THEN 'Active Medium Performer'
            WHEN us.total_posts < 10 THEN 'New User'
            ELSE 'Regular User'
        END as user_category,
        CASE 
            WHEN rp.PostTypeId = 1 AND rp.AnswerCount > 0 THEN 'Answered Question'
            WHEN rp.PostTypeId = 1 AND rp.AnswerCount = 0 THEN 'Unanswered Question'
            WHEN rp.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as post_type_grouping
    FROM RankedPosts rp
    INNER JOIN UserStats us ON rp.OwnerUserId = us.UserId
    LEFT JOIN TagAnalysis ta ON rp.cleaned_tags LIKE '%' || ta.TagName || '%'
    WHERE rp.rn = 1 
      AND us.total_posts > 0
      AND (rp.PostTypeId = 1 OR rp.PostTypeId = 2)
)
SELECT 
    ca.Id,
    ca.PostTypeId,
    ca.Title,
    ca.Score,
    ca.ViewCount,
    ca.AnswerCount,
    ca.CommentCount,
    ca.FavoriteCount,
    ca.score_category,
    ca.days_since_creation,
    ca.score_increase_percent,
    ca.Reputation,
    ca.DisplayName,
    ca.total_posts,
    ca.question_count,
    ca.answer_count,
    ca.avg_score,
    ca.total_views,
    ca.total_favorites,
    ca.TagName,
    ca.Count,
    ca.popularity_level,
    ca.user_category,
    ca.post_type_grouping,
    CASE 
        WHEN ca.days_since_creation < 30 AND ca.Score > 10 THEN 'Fresh High Score'
        WHEN ca.days_since_creation > 30 AND ca.Score > 50 THEN 'Established High Score'
        WHEN ca.days_since_creation < 7 AND ca.Score < 5 THEN 'New User Low Score'
        ELSE 'Other'
    END as performance_category,
    CONCAT(
        'User ', ca.DisplayName, 
        ' (Rep: ', ca.Reputation, ') - ', 
        CASE WHEN ca.PostTypeId = 1 THEN 'Q' ELSE 'A' END, 
        ' Score: ', ca.Score, 
        ' Views: ', ca.ViewCount, 
        ' Favs: ', ca.total_favorites,
        ' Tags: ', COALESCE(ca.TagName, 'None')
    ) as detailed_post_summary
FROM ComplexAnalysis ca
WHERE ca.total_posts >= 1
  AND ca.Score IS NOT NULL
  AND ca.Reputation IS NOT NULL
ORDER BY 
    ca.total_views DESC,
    ca.Score DESC,
    ca.days_since_creation ASC
LIMIT 100;