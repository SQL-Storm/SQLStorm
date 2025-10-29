-- {"query": "7292.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1730}
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
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_score,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END AS score_category
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        COUNT(DISTINCT p.Id) AS total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_count,
        SUM(COALESCE(p.Score, 0)) AS total_score,
        AVG(COALESCE(p.Score, 0)) AS avg_score,
        MAX(COALESCE(p.Score, 0)) AS max_score
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE WHEN t.Count > 100 THEN 'Popular' ELSE 'Regular' END AS tag_popularity,
        RANK() OVER (ORDER BY t.Count DESC) AS popularity_rank,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) AS dense_popularity_rank
    FROM Tags t
    WHERE t.Count > 10
),
ComplexPosts AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.OwnerUserId,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.score_category,
        rp.rn,
        CASE 
            WHEN rp.prev_score IS NOT NULL AND rp.prev_score > 0 THEN 
                ROUND((rp.Score - rp.prev_score) * 100.0 / rp.prev_score, 2)
            ELSE NULL 
        END AS score_change_percent,
        COALESCE(
            NULLIF(SUBSTRING(rp.Tags FROM 2 FOR CHAR_LENGTH(rp.Tags) - 2), ''), 
            ''
        ) AS cleaned_tags,
        REGEXP_REPLACE(
            COALESCE(rp.Title, ''), 
            '[[:space:]]+', ' '
        ) AS normalized_title,
        CASE 
            WHEN rp.Tags IS NOT NULL AND CHAR_LENGTH(rp.Tags) > 2 THEN 
                CARDINALITY(STRING_TO_ARRAY(SUBSTRING(rp.Tags FROM 2 FOR CHAR_LENGTH(rp.Tags) - 2), '><'))
            ELSE 0 
        END AS tag_count
    FROM RankedPosts rp
    WHERE rp.rn <= 10
),
CombinedData AS (
    SELECT 
        cp.Id,
        cp.PostTypeId,
        cp.Score,
        cp.ViewCount,
        cp.CreationDate,
        cp.OwnerUserId,
        cp.Title,
        cp.Tags,
        cp.AnswerCount,
        cp.score_category,
        cp.score_change_percent,
        cp.cleaned_tags,
        cp.normalized_title,
        cp.tag_count,
        us.Reputation,
        us.DisplayName,
        us.total_posts,
        us.question_count,
        us.answer_count,
        us.total_score,
        us.avg_score,
        us.max_score,
        ta.TagName,
        ta.Count AS tag_count_value,
        ta.tag_popularity,
        ta.popularity_rank,
        ta.dense_popularity_rank,
        CASE 
            WHEN cp.Score > us.avg_score THEN 'Above Average'
            WHEN cp.Score < us.avg_score THEN 'Below Average'
            ELSE 'Average'
        END AS score_vs_average,
        CASE 
            WHEN cp.Score >= 100 THEN 'High Impact'
            WHEN cp.Score >= 50 THEN 'Medium Impact'
            ELSE 'Low Impact'
        END AS impact_level,
        CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - cp.CreationDate)) / 86400 AS INTEGER) AS days_since_creation,
        (CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - cp.CreationDate)) / 86400 AS INTEGER) > 365) AS is_old_post
    FROM ComplexPosts cp
    LEFT JOIN UserStats us ON cp.OwnerUserId = us.UserId
    LEFT JOIN TagAnalysis ta ON cp.cleaned_tags IS NOT NULL 
        AND ta.TagName IN (
            SELECT UNNEST(STRING_TO_ARRAY(cp.cleaned_tags, '><'))
        )
),
UserTagAgg AS (
    SELECT
        cd.OwnerUserId,
        STRING_AGG(cd.TagName, ', ') FILTER (WHERE cd.TagName IS NOT NULL) AS user_tags
    FROM CombinedData cd
    GROUP BY cd.OwnerUserId
)
SELECT 
    cd.Id,
    cd.PostTypeId,
    cd.Score,
    cd.ViewCount,
    cd.CreationDate,
    cd.OwnerUserId,
    cd.Title,
    cd.Tags,
    cd.AnswerCount,
    cd.score_category,
    cd.score_change_percent,
    cd.cleaned_tags,
    cd.normalized_title,
    cd.tag_count,
    cd.Reputation,
    cd.DisplayName,
    cd.total_posts,
    cd.question_count,
    cd.answer_count,
    cd.total_score,
    cd.avg_score,
    cd.max_score,
    cd.TagName,
    cd.tag_count_value,
    cd.tag_popularity,
    cd.popularity_rank,
    cd.dense_popularity_rank,
    cd.score_vs_average,
    cd.impact_level,
    cd.days_since_creation,
    cd.is_old_post,
    ROW_NUMBER() OVER (ORDER BY cd.Score DESC) AS global_score_rank,
    RANK() OVER (PARTITION BY cd.OwnerUserId ORDER BY cd.Score DESC) AS user_score_rank,
    NTILE(4) OVER (ORDER BY cd.Score) AS score_quartile,
    CASE 
        WHEN cd.Score BETWEEN 1 AND 10 THEN '1-10'
        WHEN cd.Score BETWEEN 11 AND 50 THEN '11-50'
        WHEN cd.Score BETWEEN 51 AND 100 THEN '51-100'
        WHEN cd.Score BETWEEN 101 AND 500 THEN '101-500'
        WHEN cd.Score > 500 THEN '500+'
        ELSE 'Unknown'
    END AS score_range,
    COALESCE(
        CASE 
            WHEN cd.Score > 100 AND cd.question_count > 10 THEN 'Active Expert'
            WHEN cd.Score > 50 AND cd.question_count > 5 THEN 'Active Contributor'
            WHEN cd.Score > 0 AND cd.question_count > 0 THEN 'Contributor'
            ELSE 'Inactive'
        END, 
        'Unknown'
    ) AS user_activity_level,
    COUNT(*) OVER (PARTITION BY cd.OwnerUserId) AS user_total_posts,
    AVG(cd.Score) OVER (PARTITION BY cd.OwnerUserId) AS user_avg_score,
    uta.user_tags,
    CASE 
        WHEN cd.is_old_post AND cd.Score < 10 THEN 'Underperforming Old'
        WHEN cd.is_old_post AND cd.Score >= 10 THEN 'Good Old'
        WHEN NOT cd.is_old_post AND cd.Score < 10 THEN 'Underperforming New'
        WHEN NOT cd.is_old_post AND cd.Score >= 10 THEN 'Good New'
        ELSE 'Unknown'
    END AS post_performance_category
FROM CombinedData cd
LEFT JOIN UserTagAgg uta ON cd.OwnerUserId = uta.OwnerUserId
WHERE cd.Reputation > 0 
    AND cd.total_posts > 0
    AND cd.OwnerUserId IS NOT NULL
    AND (
        cd.is_old_post 
        OR cd.score_change_percent IS NOT NULL 
        OR cd.normalized_title IS NOT NULL
    )
GROUP BY
    cd.Id,
    cd.PostTypeId,
    cd.Score,
    cd.ViewCount,
    cd.CreationDate,
    cd.OwnerUserId,
    cd.Title,
    cd.Tags,
    cd.AnswerCount,
    cd.score_category,
    cd.score_change_percent,
    cd.cleaned_tags,
    cd.normalized_title,
    cd.tag_count,
    cd.Reputation,
    cd.DisplayName,
    cd.total_posts,
    cd.question_count,
    cd.answer_count,
    cd.total_score,
    cd.avg_score,
    cd.max_score,
    cd.TagName,
    cd.tag_count_value,
    cd.tag_popularity,
    cd.popularity_rank,
    cd.dense_popularity_rank,
    cd.score_vs_average,
    cd.impact_level,
    cd.days_since_creation,
    cd.is_old_post,
    uta.user_tags
HAVING cd.total_score > 0
ORDER BY 
    cd.Score DESC,
    cd.CreationDate DESC,
    cd.Reputation DESC
LIMIT 500;