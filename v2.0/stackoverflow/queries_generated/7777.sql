-- {"query": "7777.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2086} 
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
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as avg_score_3,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END as score_category,
        COALESCE(p.Tags, '') as normalized_tags,
        IIF(p.PostTypeId = 1 AND p.AnswerCount IS NOT NULL, p.AnswerCount, 0) as answer_count_or_zero
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
    SELECT 
        u.Id as user_id,
        u.DisplayName,
        u.Reputation,
        u.ViewCount,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT r.Id) as reputation_changes_count,
        COUNT(DISTINCT p.Id) as post_count,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as question_count,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as answer_count,
        MAX(p.CreationDate) as latest_activity,
        STRING_AGG(DISTINCT p.Title, '; ') as recent_titles,
        CASE 
            WHEN u.ViewCount > 10000 THEN 'Popular'
            WHEN u.Reputation > 10000 THEN 'Reputable'
            WHEN u.UpVotes > 1000 THEN 'Active'
            ELSE 'Regular'
        END as user_category
    FROM Users u
    LEFT JOIN PostHistory r ON u.Id = r.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.ViewCount, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        ISNULL(p.Title, 'No Title') as tag_title,
        CASE 
            WHEN t.Count > 100 THEN 'Trending'
            WHEN t.Count > 50 THEN 'Popular'
            WHEN t.Count > 10 THEN 'Common'
            ELSE 'Rare'
        END as tag_category,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as popularity_rank
    FROM Tags t
    LEFT JOIN Posts p ON t.WikiPostId = p.Id
),
ComplexJoin AS (
    SELECT 
        rp.Id as post_id,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.OwnerUserId,
        rp.Title,
        rp.Tags,
        rp.score_category,
        us.DisplayName as owner_name,
        us.Reputation as owner_reputation,
        us.user_category,
        ta.TagName,
        ta.tag_category,
        ta.popularity_rank,
        CASE 
            WHEN rp.prev_score IS NOT NULL AND rp.prev_score > 0 
            THEN (rp.Score - rp.prev_score) * 100.0 / rp.prev_score 
            ELSE NULL 
        END as score_change_percent,
        IIF(rp.avg_score_3 IS NOT NULL, rp.avg_score_3, 0) as rolling_avg_score,
        IIF(rp.answer_count_or_zero > 0, 
            CAST(rp.AnswerCount AS FLOAT) / CAST(rp.answer_count_or_zero AS FLOAT), 
            0) as answer_ratio,
        CASE 
            WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN rp.Score >= 10 THEN 'High Score'
            WHEN rp.Score > 0 THEN 'Positive Score'
            ELSE 'Low Score'
        END as post_status,
        CONCAT(rp.Title, ' (', 
               IIF(rp.Tags IS NOT NULL AND rp.Tags != '', 
                   STRING_AGG(SUBSTRING(rp.Tags, 2, LEN(rp.Tags)-2), ', '), 
                   'No Tags'), 
               ')') as enhanced_title,
        IIF(rp.Score > 0 AND rp.Score < 10, 'Low to Medium', 
            IIF(rp.Score >= 10 AND rp.Score < 100, 'Medium to High', 
                IIF(rp.Score >= 100, 'Very High', 'No Score'))) as score_band,
        IIF(rp.PostTypeId = 1, 'Question', 'Answer') as post_type_desc
    FROM RankedPosts rp
    LEFT JOIN UserStats us ON rp.OwnerUserId = us.user_id
    LEFT JOIN Tags t ON rp.Tags LIKE '%' + t.TagName + '%'
    LEFT JOIN TagAnalysis ta ON t.TagName = ta.TagName
    WHERE rp.rn = 1
      AND rp.Score IS NOT NULL
      AND us.user_id IS NOT NULL
      AND (
          (rp.PostTypeId = 1 AND rp.AnswerCount >= 0) OR
          (rp.PostTypeId = 2 AND rp.AnswerCount IS NULL)
      )
    GROUP BY 
        rp.Id, rp.Score, rp.ViewCount, rp.CreationDate, rp.OwnerUserId, 
        rp.Title, rp.Tags, rp.score_category, 
        us.DisplayName, us.Reputation, us.user_category,
        ta.TagName, ta.tag_category, ta.popularity_rank,
        rp.prev_score, rp.avg_score_3, rp.AnswerCount, rp.answer_count_or_zero,
        rp.ClosedDate, rp.PostTypeId
)
SELECT 
    cj.post_id,
    cj.Score,
    cj.ViewCount,
    cj.CreationDate,
    cj.owner_name,
    cj.owner_reputation,
    cj.user_category,
    cj.TagName,
    cj.tag_category,
    cj.popularity_rank,
    cj.score_change_percent,
    cj.rolling_avg_score,
    cj.answer_ratio,
    cj.post_status,
    cj.enhanced_title,
    cj.score_band,
    cj.post_type_desc,
    COUNT(*) OVER() as total_posts_processed,
    RANK() OVER (ORDER BY cj.Score DESC) as score_rank,
    DENSE_RANK() OVER (ORDER BY cj.owner_reputation DESC) as reputation_rank,
    ROW_NUMBER() OVER (ORDER BY cj.CreationDate DESC) as chronological_order,
    NTILE(4) OVER (ORDER BY cj.Score) as score_quartile,
    LAG(cj.Score) OVER (ORDER BY cj.CreationDate) as prior_score,
    LEAD(cj.Score) OVER (ORDER BY cj.CreationDate) as next_score,
    CASE 
        WHEN cj.Score > (
            SELECT AVG(Score) 
            FROM Posts 
            WHERE PostTypeId = 1 
            AND Score > 0
        ) THEN 'Above Average' 
        ELSE 'Below Average' 
    END as avg_performance,
    IIF(cj.Score > 50, 
        (SELECT COUNT(*) FROM Posts p WHERE p.Score > cj.Score), 
        0) as higher_than_count,
    IIF(cj.Score > 0 AND cj.ViewCount > 0, 
        CAST(cj.Score AS FLOAT) / CAST(cj.ViewCount AS FLOAT), 
        0) as score_to_view_ratio,
    COALESCE(cj.Enhanced_Title, 'No title available') as final_title,
    CASE 
        WHEN cj.post_type_desc = 'Question' AND cj.answer_count_or_zero > 0 THEN 
            CAST(cj.AnswerCount AS FLOAT) / CAST(cj.answer_count_or_zero AS FLOAT)
        ELSE 0 
    END as question_answer_ratio,
    ISNULL(cj.TagName, 'Uncategorized') as tag_classification,
    ISNULL(CAST(cj.popularity_rank AS VARCHAR(10)), 'Unknown') as rank_info,
    CASE 
        WHEN cj.user_category = 'Popular' THEN 'High Engagement'
        WHEN cj.user_category = 'Reputable' THEN 'Moderate Engagement'
        WHEN cj.user_category = 'Active' THEN 'Regular Engagement'
        WHEN cj.user_category = 'Regular' THEN 'Low Engagement'
        ELSE 'Unknown'
    END as engagement_level,
    CASE 
        WHEN cj.post_status IN ('Closed', 'High Score') THEN 'Status Alert'
        WHEN cj.post_status = 'Positive Score' THEN 'Positive Activity'
        ELSE 'Standard Activity'
    END as activity_status,
    IIF(cj.score_band IN ('High', 'Medium to High', 'Very High'), 
        'Important Post', 
        'Routine Post') as priority_classification,
    IIF(cj.Score > 0, 
        (SELECT TOP 1 p.Score 
         FROM Posts p 
         WHERE p.OwnerUserId = cj.OwnerUserId 
         ORDER BY p.CreationDate DESC), 
        0) as latest_user_score
FROM ComplexJoin cj
WHERE cj.score > 0
  AND cj.viewcount > 0
  AND cj.owner_name IS NOT NULL
  AND cj.TagName IS NOT NULL
  AND cj.enhanced_title IS NOT NULL
HAVING 
    (cj.score_change_percent IS NULL OR cj.score_change_percent > -100)
    AND (cj.rolling_avg_score IS NULL OR cj.rolling_avg_score > 0)
    AND cj.answer_ratio > -1
    AND cj.answer_ratio < 10
ORDER BY 
    cj.CreationDate DESC,
    cj.Score DESC,
    cj.ViewCount DESC
OFFSET 0 ROWS
FETCH NEXT 1000 ROWS ONLY;