-- {"query": "7775.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1851} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.LastEditDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END as score_category,
        COALESCE(p.Tags, '') as clean_tags,
        TRIM(BOTH '<>' FROM COALESCE(p.Tags, '')) as trimmed_tags,
        STRING_TO_ARRAY(TRIM(BOTH '<>' FROM COALESCE(p.Tags, '')), '><') as tag_array
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= '2020-01-01'
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as post_count,
        SUM(p.Score) as total_score,
        AVG(p.Score) as avg_score,
        MAX(p.CreationDate) as latest_post_date,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Veteran'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Experienced'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Active'
            ELSE 'New'
        END as user_status
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= '2015-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 500 THEN 'Well-Known'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END as tag_popularity,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) as prev_count
    FROM Tags t
    WHERE t.Count > 10
),
ComplexQuestionAnalysis AS (
    SELECT 
        rp.Id,
        rp.Title,
        rp.Score,
        rp.ViewCount,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.CreationDate,
        rp.LastActivityDate,
        rp.OwnerUserId,
        CASE 
            WHEN rp.AnswerCount > 0 THEN 
                (rp.Score * 1.0 / NULLIF(rp.AnswerCount, 0)) 
            ELSE 0 
        END as score_per_answer,
        CASE 
            WHEN rp.CommentCount > 0 THEN 
                (rp.Score * 1.0 / NULLIF(rp.CommentCount, 0)) 
            ELSE 0 
        END as score_per_comment,
        CASE 
            WHEN rp.ViewCount > 0 THEN 
                (rp.Score * 1.0 / NULLIF(rp.ViewCount, 0)) 
            ELSE 0 
        END as score_per_view,
        CASE 
            WHEN rp.FavoriteCount > 0 THEN 
                (rp.Score * 1.0 / NULLIF(rp.FavoriteCount, 0)) 
            ELSE 0 
        END as score_per_favorite,
        rp.rn as post_rank,
        rp.prev_score as previous_score,
        CASE 
            WHEN (rp.Score - COALESCE(rp.prev_score, 0)) > 50 THEN 'Significant Increase'
            WHEN (rp.Score - COALESCE(rp.prev_score, 0)) < -50 THEN 'Significant Decrease'
            WHEN ABS(rp.Score - COALESCE(rp.prev_score, 0)) < 10 THEN 'Stable'
            ELSE 'Moderate Change'
        END as score_trend,
        rp.clean_tags,
        rp.trimmed_tags,
        rp.tag_array,
        CASE 
            WHEN ARRAY_LENGTH(rp.tag_array, 1) > 3 THEN 'Many Tags'
            WHEN ARRAY_LENGTH(rp.tag_array, 1) > 1 THEN 'Several Tags'
            ELSE 'Few Tags'
        END as tag_quantity
    FROM RankedPosts rp
    WHERE rp.rn <= 5
)
SELECT 
    'Performance Benchmark Results' as report_title,
    COUNT(*) as total_questions,
    COUNT(DISTINCT cqa.OwnerUserId) as unique_authors,
    AVG(cqa.Score) as avg_score,
    MAX(cqa.Score) as max_score,
    MIN(cqa.CreationDate) as earliest_post,
    MAX(cqa.CreationDate) as latest_post,
    AVG(cqa.score_per_answer) as avg_score_per_answer,
    AVG(cqa.score_per_comment) as avg_score_per_comment,
    AVG(cqa.score_per_view) as avg_score_per_view,
    AVG(cqa.score_per_favorite) as avg_score_per_favorite,
    STRING_AGG(DISTINCT us.user_status, ', ') as user_statuses,
    STRING_AGG(DISTINCT ta.tag_popularity, ', ') as tag_popularities,
    COUNT(DISTINCT CASE WHEN cqa.score_trend = 'Significant Increase' THEN cqa.Id END) as significant_increases,
    COUNT(DISTINCT CASE WHEN cqa.score_trend = 'Significant Decrease' THEN cqa.Id END) as significant_decreases,
    COUNT(DISTINCT CASE WHEN cqa.score_trend = 'Stable' THEN cqa.Id END) as stable_posts,
    COUNT(DISTINCT CASE WHEN cqa.tag_quantity = 'Many Tags' THEN cqa.Id END) as many_tag_posts,
    COUNT(DISTINCT CASE WHEN cqa.tag_quantity = 'Several Tags' THEN cqa.Id END) as several_tag_posts,
    COUNT(DISTINCT CASE WHEN cqa.tag_quantity = 'Few Tags' THEN cqa.Id END) as few_tag_posts
FROM ComplexQuestionAnalysis cqa
LEFT JOIN UserStats us ON cqa.OwnerUserId = us.UserId
LEFT JOIN TagAnalysis ta ON EXISTS (
    SELECT 1 
    FROM UNNEST(cqa.tag_array) as tag 
    WHERE tag = ta.TagName
)
WHERE cqa.PostTypeId = 1
  AND cqa.CreationDate >= '2020-01-01'
  AND cqa.CreationDate < '2023-01-01'
  AND COALESCE(cqa.Score, 0) > 0
  AND cqa.score_trend IS NOT NULL
  AND cqa.tag_quantity IS NOT NULL
  AND EXISTS (
    SELECT 1 
    FROM Posts p 
    WHERE p.Id = cqa.Id 
      AND p.PostTypeId = 1
      AND p.AnswerCount >= 0
  )
  AND cqa.OwnerUserId IN (
    SELECT Id 
    FROM Users 
    WHERE AccountId IS NOT NULL 
      AND Reputation >= 1000
  )
  AND NOT EXISTS (
    SELECT 1 
    FROM Posts p 
    WHERE p.Id = cqa.Id 
      AND (p.ClosedDate IS NOT NULL OR p.CommunityOwnedDate IS NOT NULL)
  )
  AND (ARRAY_LENGTH(cqa.tag_array, 1) IS NULL OR ARRAY_LENGTH(cqa.tag_array, 1) > 0)
  AND (
    SELECT COUNT(*) 
    FROM Comments cm 
    WHERE cm.PostId = cqa.Id 
      AND cm.CreationDate >= '2020-01-01'
  ) >= 0
  AND cqa.Id IN (
    SELECT DISTINCT ph.PostId 
    FROM PostHistory ph 
    WHERE ph.PostId = cqa.Id 
      AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
      AND ph.CreationDate >= '2020-01-01'
  )
  AND (
    SELECT COUNT(*) 
    FROM Votes v 
    WHERE v.PostId = cqa.Id 
      AND v.VoteTypeId IN (1, 2, 3)
  ) IS NOT NULL
ORDER BY cqa.Score DESC
LIMIT 100;