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
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_score,
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_avg_score,
        CASE 
            WHEN p.Score > 100 THEN 'Highly_Voted'
            WHEN p.Score > 50 THEN 'Moderately_Voted'
            WHEN p.Score > 10 THEN 'Low_Voted'
            ELSE 'Very_Low_Voted'
        END AS vote_category,
        COALESCE(p.Tags, '') AS cleaned_tags,
        TRIM(BOTH '<>' FROM SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2))) AS tag_list,
        -- string_agg cannot be used as a window function in many engines; aggregate per user in a subquery instead
        NULL AS user_tags
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserTagsPerUser AS (
    SELECT
        OwnerUserId,
        STRING_AGG(Tags, ', ') AS user_tags
    FROM Posts
    WHERE Tags IS NOT NULL
    GROUP BY OwnerUserId
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT rp.Id) AS post_count,
        SUM(COALESCE(rp.Score, 0)) AS total_score,
        AVG(COALESCE(rp.Score, 0)) AS avg_score,
        MAX(COALESCE(rp.Score, 0)) AS max_score,
        STRING_AGG(DISTINCT rp.vote_category, ', ') AS categories,
        STRING_AGG(DISTINCT TRIM(BOTH '<>' FROM SUBSTRING(rp.tag_list FROM 1 FOR (POSITION('>' IN rp.tag_list) - 1))), ', ') AS first_tags,
        ut.user_tags
    FROM Users u
    LEFT JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
    LEFT JOIN UserTagsPerUser ut ON u.Id = ut.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, ut.user_tags
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS tag_count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular' 
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Common'
            ELSE 'Rare'
        END AS popularity_level,
        COALESCE(t.WikiPostId, 0) AS has_wiki,
        COALESCE(t.ExcerptPostId, 0) AS has_excerpt
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
        END AS user_performance_level,
        CASE 
            WHEN ta.tag_count > 1000 THEN 
                (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || ta.TagName || '%')
            ELSE 0 
        END AS post_with_tag,
        CASE 
            WHEN us.post_count > 50 THEN 
                (SELECT AVG(rp.Score) FROM RankedPosts rp WHERE rp.OwnerUserId = us.UserId AND rp.PostTypeId = 1)
            ELSE NULL 
        END AS avg_question_score
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
        DENSE_RANK() OVER (ORDER BY cj.total_score DESC) AS score_rank,
        ROW_NUMBER() OVER (PARTITION BY cj.user_performance_level ORDER BY cj.Reputation DESC) AS rep_rank_in_performance,
        NTILE(10) OVER (ORDER BY cj.tag_count DESC) AS tag_decile,
        CASE 
            WHEN cj.total_score > 1000 AND cj.post_count > 20 THEN 'Active_Power'
            WHEN cj.total_score > 500 AND cj.post_count > 10 THEN 'Active_Moderate'
            WHEN cj.total_score > 100 THEN 'Active_Low'
            ELSE 'Inactive'
        END AS activity_status,
        CONCAT(
            'User ', CAST(cj.UserId AS text), 
            ' with reputation ', CAST(cj.Reputation AS text), 
            ' and ', CAST(cj.post_count AS text), 
            ' posts, has created ', CAST(cj.total_score AS text), 
            ' points across ', 
            CASE WHEN cj.avg_question_score IS NOT NULL THEN 'questions with avg score ' ELSE '' END,
            CASE WHEN cj.avg_question_score IS NOT NULL THEN CAST(cj.avg_question_score AS text) ELSE '' END,
            ' for tag ', cj.TagName, 
            ' which has ', CAST(cj.tag_count AS text), 
            ' occurances and is ', cj.popularity_level
        ) AS detailed_analysis
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
    END AS elite_tagger,
    COALESCE(
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = fa.UserId AND p.PostTypeId = 1 AND p.Score > 100), 
        0
    ) AS high_value_questions,
    COALESCE(
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = fa.UserId AND p.PostTypeId = 2 AND p.Score > 50), 
        0
    ) AS high_value_answers
FROM FinalAnalysis fa
WHERE fa.TagName IS NOT NULL
  AND fa.total_score > 0
  AND fa.post_count > 0
  AND (fa.avg_question_score > 10 OR fa.avg_question_score IS NULL)

UNION ALL

SELECT 
    CAST(NULL AS bigint) AS UserId,
    'Overall_Avg' AS DisplayName,
    AVG(Reputation) AS Reputation,
    AVG(post_count) AS post_count,
    AVG(total_score) AS total_score,
    AVG(avg_score) AS avg_score,
    AVG(max_score) AS max_score,
    CAST(NULL AS text) AS categories,
    CAST(NULL AS text) AS first_tags,
    CAST(NULL AS text) AS TagName,
    CAST(NULL AS bigint) AS tag_count,
    CAST(NULL AS text) AS popularity_level,
    CAST(NULL AS bigint) AS has_wiki,
    CAST(NULL AS bigint) AS has_excerpt,
    CAST(NULL AS text) AS user_performance_level,
    CAST(NULL AS bigint) AS post_with_tag,
    CAST(NULL AS numeric) AS avg_question_score,
    CAST(NULL AS bigint) AS score_rank,
    CAST(NULL AS bigint) AS rep_rank_in_performance,
    CAST(NULL AS integer) AS tag_decile,
    'Average_User' AS activity_status,
    CAST(NULL AS text) AS detailed_analysis,
    CAST(NULL AS text) AS elite_tagger,
    CAST(NULL AS bigint) AS high_value_questions,
    CAST(NULL AS bigint) AS high_value_answers
FROM FinalAnalysis
ORDER BY total_score DESC NULLS LAST, post_count DESC NULLS LAST, tag_count DESC NULLS LAST
LIMIT 1000;