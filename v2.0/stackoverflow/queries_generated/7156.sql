-- {"query": "7156.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2122} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        LAG(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_views,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as avg_score_3posts,
        NTILE(4) OVER (ORDER BY p.Score) as score_quartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
PostStats AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.Title,
        rp.Tags,
        rp.OwnerUserId,
        rp.AcceptedAnswerId,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.rn,
        rp.prev_score,
        rp.prev_views,
        rp.avg_score_3posts,
        rp.score_quartile,
        DATEDIFF('DAY', rp.CreationDate, CURRENT_TIMESTAMP) as days_since_creation,
        COALESCE(rp.prev_score, 0) - COALESCE(rp.Score, 0) as score_change,
        CASE 
            WHEN rp.Score > 100 THEN 'High'
            WHEN rp.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END as score_category,
        CASE 
            WHEN rp.Tags IS NOT NULL AND rp.Tags != '' THEN 
                (SELECT COUNT(*) FROM UNNEST(SPLIT(rp.Tags, '>')) WHERE LENGTH(TRIM(value)) > 0)
            ELSE 0
        END as tag_count,
        CASE 
            WHEN rp.AnswerCount > 10 THEN 'Many Answers'
            WHEN rp.AnswerCount > 5 THEN 'Some Answers'
            ELSE 'Few Answers'
        END as answer_category
    FROM RankedPosts rp
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
        SUM(COALESCE(p.Score, 0)) as total_score,
        MAX(COALESCE(p.CreationDate, u.CreationDate)) as last_activity,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Expert'
            WHEN u.Reputation > 1000 THEN 'Advanced'
            WHEN u.Reputation > 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END as reputation_level,
        AVG(COALESCE(p.Score, 0)) as avg_post_score
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT 
        ps.Id,
        ps.PostTypeId,
        ps.Score,
        ps.ViewCount,
        ps.CreationDate,
        ps.Title,
        ps.Tags,
        ps.OwnerUserId,
        ps.AcceptedAnswerId,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.rn,
        ps.prev_score,
        ps.prev_views,
        ps.avg_score_3posts,
        ps.score_quartile,
        ps.days_since_creation,
        ps.score_change,
        ps.score_category,
        ps.tag_count,
        ps.answer_category,
        ua.reputation_level,
        ua.avg_post_score,
        ua.post_count,
        CASE 
            WHEN ps.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 1
            ELSE 0
        END as above_avg_question,
        CASE 
            WHEN ps.PostTypeId = 2 AND ps.AcceptedAnswerId IS NOT NULL THEN 1
            ELSE 0
        END as has_accepted_answer,
        CASE 
            WHEN ps.CommentCount > 5 THEN 'Many Comments'
            WHEN ps.CommentCount > 2 THEN 'Some Comments'
            ELSE 'Few Comments'
        END as comment_category,
        DENSE_RANK() OVER (ORDER BY ps.Score DESC) as score_rank
    FROM PostStats ps
    JOIN UserActivity ua ON ps.OwnerUserId = ua.UserId
    WHERE ps.days_since_creation <= 365
),
FinalAnalysis AS (
    SELECT 
        pa.Id,
        pa.PostTypeId,
        pa.Score,
        pa.ViewCount,
        pa.CreationDate,
        pa.Title,
        pa.Tags,
        pa.OwnerUserId,
        pa.AcceptedAnswerId,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.rn,
        pa.prev_score,
        pa.prev_views,
        pa.avg_score_3posts,
        pa.score_quartile,
        pa.days_since_creation,
        pa.score_change,
        pa.score_category,
        pa.tag_count,
        pa.answer_category,
        pa.reputation_level,
        pa.avg_post_score,
        pa.post_count,
        pa.above_avg_question,
        pa.has_accepted_answer,
        pa.comment_category,
        pa.score_rank,
        LTRIM(RTRIM(REGEXP_REPLACE(
            COALESCE(pa.Title, '') 
            || ' | ' || COALESCE(pa.Tags, '') 
            || ' | ' || COALESCE(pa.comment_category, ''), 
            '[[:space:]]+', ' ', 'g'
        ))) as title_tag_desc,
        CASE 
            WHEN pa.score_change > 50 AND pa.prev_views > pa.ViewCount THEN 'Improving and Growing'
            WHEN pa.score_change < -50 AND pa.prev_views < pa.ViewCount THEN 'Declining and Shrinking'
            WHEN pa.score_change > 0 THEN 'Improving'
            ELSE 'Stable'
        END as performance_trend,
        CASE 
            WHEN pa.post_count > 50 THEN 'Heavy Poster'
            WHEN pa.post_count > 20 THEN 'Moderate Poster'
            WHEN pa.post_count > 5 THEN 'Light Poster'
            ELSE 'New Poster'
        END as posting_frequency,
        IIF(pa.Score > 100 AND pa.ViewCount > 1000, 'Viral Potential', 'Normal') as potential_category,
        COALESCE(pa.Score, 0) * COALESCE(pa.ViewCount, 1) as score_view_product,
        RANK() OVER (PARTITION BY pa.reputation_level ORDER BY pa.Score DESC) as rank_by_reputation,
        ROW_NUMBER() OVER (ORDER BY pa.Score DESC) as global_rank
    FROM PostAnalysis pa
)
SELECT 
    fa.Id,
    fa.PostTypeId,
    fa.Score,
    fa.ViewCount,
    fa.CreationDate,
    SUBSTRING(fa.Title, 1, 100) as Title,
    fa.Tags,
    fa.OwnerUserId,
    fa.AcceptedAnswerId,
    fa.AnswerCount,
    fa.CommentCount,
    fa.FavoriteCount,
    fa.rn,
    fa.prev_score,
    fa.prev_views,
    fa.avg_score_3posts,
    fa.score_quartile,
    fa.days_since_creation,
    fa.score_change,
    fa.score_category,
    fa.tag_count,
    fa.answer_category,
    fa.reputation_level,
    fa.avg_post_score,
    fa.post_count,
    fa.above_avg_question,
    fa.has_accepted_answer,
    fa.comment_category,
    fa.score_rank,
    fa.title_tag_desc,
    fa.performance_trend,
    fa.posting_frequency,
    fa.potential_category,
    fa.score_view_product,
    fa.rank_by_reputation,
    fa.global_rank,
    CASE 
        WHEN (fa.score_change > 0 OR fa.prev_score > 0) AND (fa.ViewCount > 100 OR fa.FavoriteCount > 5) THEN 'High Engagement'
        WHEN (fa.score_change < 0 OR fa.prev_score < 0) AND (fa.ViewCount < 10 OR fa.FavoriteCount < 1) THEN 'Low Engagement'
        ELSE 'Medium Engagement'
    END as engagement_level,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = fa.OwnerUserId AND CreationDate > fa.CreationDate) as subsequent_post_count,
    (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = fa.OwnerUserId AND PostTypeId = 1) as user_avg_question_score,
    (SELECT COUNT(*) FROM Comments WHERE PostId = fa.Id AND Score > 0) as positive_comments,
    CASE 
        WHEN REGEXP_MATCHES(fa.Tags, '.*[0-9]+.*') THEN 'Numeric Tag Present'
        ELSE 'No Numeric Tag'
    END as numeric_tag_status,
    IIF(fa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 1.5, 'Top Performer', 'Regular') as performance_status,
    EXTRACT(YEAR FROM fa.CreationDate) as creation_year,
    EXTRACT(MONTH FROM fa.CreationDate) as creation_month,
    (fa.Score + 1) * (fa.ViewCount + 1) * (fa.FavoriteCount + 1) as composite_score_metric
FROM FinalAnalysis fa
WHERE fa.days_since_creation <= 365
  AND (fa.PostTypeId = 1 OR fa.PostTypeId = 2)
  AND fa.score_category IS NOT NULL
  AND fa.tags IS NOT NULL
  AND fa.tags != ''
  AND fa.Score >= 0
  AND fa.ViewCount >= 0
ORDER BY fa.Score DESC, fa.CreationDate DESC
LIMIT 1000;