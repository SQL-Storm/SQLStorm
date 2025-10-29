-- {"query": "7716.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1845} 
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
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as rolling_avg_score,
        CASE 
            WHEN p.Score > 100 THEN 'Highly_Voted'
            WHEN p.Score > 50 THEN 'Moderately_Voted'
            WHEN p.Score > 10 THEN 'Low_Voted'
            ELSE 'Very_Low_Voted'
        END as vote_category,
        COALESCE(p.Tags, '') as cleaned_tags,
        TRIM(BOTH '<>' FROM SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2)) as tag_list,
        STRING_AGG(p.Tags, ', ') OVER (PARTITION BY p.OwnerUserId) as user_tags
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
        COUNT(DISTINCT rp.Id) as post_count,
        SUM(COALESCE(rp.Score, 0)) as total_score,
        AVG(COALESCE(rp.Score, 0)) as avg_score,
        MAX(COALESCE(rp.Score, 0)) as max_score,
        STRING_AGG(DISTINCT rp.vote_category, ', ') as categories,
        STRING_AGG(DISTINCT TRIM(BOTH '<>' FROM SUBSTRING(rp.tag_list, 1, POSITION('>' IN rp.tag_list) - 1)), ', ') as first_tags
    FROM Users u
    LEFT JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as tag_count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular' 
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Common'
            ELSE 'Rare'
        END as popularity_level,
        COALESCE(t.WikiPostId, 0) as has_wiki,
        COALESCE(t.ExcerptPostId, 0) as has_excerpt
    FROM Tags t
    WHERE t.Count > 50
),
ComplexJoins AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.post_count,
        us.total_score,
        us.avg_score,
        us.max_score,
        us.categories,
        us.first_tags,
        ta.TagName,
        ta.tag_count,
        ta.popularity_level,
        ta.has_wiki,
        ta.has_excerpt,
        CASE 
            WHEN us.total_score > (SELECT AVG(total_score) FROM UserStats) THEN 'Above_Avg'
            WHEN us.total_score < (SELECT AVG(total_score) FROM UserStats) THEN 'Below_Avg'
            ELSE 'Avg'
        END as user_performance_level,
        CASE 
            WHEN ta.tag_count > 1000 THEN 
                (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || ta.TagName || '%')
            ELSE 0 
        END as post_with_tag,
        CASE 
            WHEN us.post_count > 50 THEN 
                (SELECT AVG(rp.Score) FROM RankedPosts rp WHERE rp.OwnerUserId = us.UserId AND rp.PostTypeId = 1)
            ELSE NULL 
        END as avg_question_score
    FROM UserStats us
    CROSS JOIN TagAnalysis ta
    WHERE us.Reputation BETWEEN 1000 AND 10000
      AND ta.popularity_level IN ('Popular', 'Moderate')
),
FinalAnalysis AS (
    SELECT 
        cj.UserId,
        cj.DisplayName,
        cj.Reputation,
        cj.post_count,
        cj.total_score,
        cj.avg_score,
        cj.max_score,
        cj.categories,
        cj.first_tags,
        cj.TagName,
        cj.tag_count,
        cj.popularity_level,
        cj.has_wiki,
        cj.has_excerpt,
        cj.user_performance_level,
        cj.post_with_tag,
        cj.avg_question_score,
        DENSE_RANK() OVER (ORDER BY cj.total_score DESC) as score_rank,
        ROW_NUMBER() OVER (PARTITION BY cj.user_performance_level ORDER BY cj.Reputation DESC) as rep_rank_in_performance,
        NTILE(10) OVER (ORDER BY cj.tag_count DESC) as tag_decile,
        CASE 
            WHEN cj.total_score > 1000 AND cj.post_count > 20 THEN 'Active_Power'
            WHEN cj.total_score > 500 AND cj.post_count > 10 THEN 'Active_Moderate'
            WHEN cj.total_score > 100 THEN 'Active_Low'
            ELSE 'Inactive'
        END as activity_status,
        CONCAT(
            'User ', cj.UserId, 
            ' with reputation ', cj.Reputation, 
            ' and ', cj.post_count, 
            ' posts, has created ', cj.total_score, 
            ' points across ', 
            CASE WHEN cj.avg_question_score IS NOT NULL THEN 'questions with avg score ' ELSE '' END,
            CASE WHEN cj.avg_question_score IS NOT NULL THEN CAST(cj.avg_question_score AS VARCHAR) ELSE '' END,
            ' for tag ', cj.TagName, 
            ' which has ', cj.tag_count, 
            ' occurances and is ', cj.popularity_level
        ) as detailed_analysis
    FROM ComplexJoins cj
    WHERE cj.post_with_tag > 0
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.post_count,
    fa.total_score,
    fa.avg_score,
    fa.max_score,
    fa.categories,
    fa.first_tags,
    fa.TagName,
    fa.tag_count,
    fa.popularity_level,
    fa.has_wiki,
    fa.has_excerpt,
    fa.user_performance_level,
    fa.post_with_tag,
    fa.avg_question_score,
    fa.score_rank,
    fa.rep_rank_in_performance,
    fa.tag_decile,
    fa.activity_status,
    fa.detailed_analysis,
    CASE 
        WHEN fa.score_rank <= 100 THEN 'Top_100_Scorer'
        WHEN fa.score_rank <= 1000 THEN 'Top_1000_Scorer'
        ELSE NULL 
    END as elite_tagger,
    COALESCE(
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = fa.UserId AND p.PostTypeId = 1 AND p.Score > 100), 
        0
    ) as high_value_questions,
    COALESCE(
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = fa.UserId AND p.PostTypeId = 2 AND p.Score > 50), 
        0
    ) as high_value_answers
FROM FinalAnalysis fa
WHERE fa.TagName IS NOT NULL
  AND fa.total_score > 0
  AND fa.post_count > 0
  AND (fa.avg_question_score > 10 OR fa.avg_question_score IS NULL)
UNION ALL
SELECT 
    NULL as UserId,
    'Overall_Avg' as DisplayName,
    AVG(Reputation) as Reputation,
    AVG(post_count) as post_count,
    AVG(total_score) as total_score,
    AVG(avg_score) as avg_score,
    AVG(max_score) as max_score,
    NULL as categories,
    NULL as first_tags,
    NULL as TagName,
    NULL as tag_count,
    NULL as popularity_level,
    NULL as has_wiki,
    NULL as has_excerpt,
    NULL as user_performance_level,
    NULL as post_with_tag,
    NULL as avg_question_score,
    NULL as score_rank,
    NULL as rep_rank_in_performance,
    NULL as tag_decile,
    'Average_User' as activity_status,
    NULL as detailed_analysis,
    NULL as elite_tagger,
    NULL as high_value_questions,
    NULL as high_value_answers
FROM FinalAnalysis
GROUP BY 'Overall_Avg'
ORDER BY total_score DESC, post_count DESC, tag_count DESC
LIMIT 1000;