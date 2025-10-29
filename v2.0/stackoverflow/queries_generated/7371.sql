-- {"query": "7371.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1331} 
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
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as avg_score_3posts,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 10 THEN 'Medium'
            ELSE 'Low'
        END as score_category,
        COALESCE(p.Title, '') as title_or_empty,
        CONCAT('Post_', p.Id, '_by_', COALESCE(u.DisplayName, 'Unknown')) as post_identifier
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
),
FilteredPosts AS (
    SELECT 
        rp.*,
        CASE 
            WHEN rp.prev_score IS NOT NULL AND rp.prev_score > 0 THEN (rp.Score - rp.prev_score) * 100.0 / rp.prev_score
            ELSE NULL
        END as score_growth_pct,
        CASE 
            WHEN rp.avg_score_3posts > 50 THEN 'Consistently High'
            WHEN rp.avg_score_3posts > 10 THEN 'Moderate Trend'
            ELSE 'Low Volume'
        END as trending_status
    FROM RankedPosts rp
    WHERE rp.rn <= 5
),
TagAnalysis AS (
    SELECT 
        fp.*,
        CASE 
            WHEN fp.Tags IS NOT NULL AND fp.Tags != '' THEN 
                ARRAY_LENGTH(string_to_array(trim(trim(fp.Tags, '<'), '>'), '><'), 1)
            ELSE 0
        END as tag_count,
        CASE 
            WHEN fp.Tags IS NOT NULL AND fp.Tags != '' 
            THEN string_to_array(trim(trim(fp.Tags, '<'), '>'), '><')
            ELSE ARRAY[]::varchar[]
        END as tag_array,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = fp.Id AND p2.PostTypeId = 2) as answer_count_corrected
    FROM FilteredPosts fp
),
ComplexCalculations AS (
    SELECT 
        ta.*,
        ta.score_growth_pct * ta.tag_count as weighted_growth,
        ta.answer_count_corrected * ta.Score as engagement_score,
        COALESCE(ta.Title, 'No Title') as final_title,
        CASE 
            WHEN ta.score_category = 'High' AND ta.trending_status = 'Consistently High' THEN 'Star Performer'
            WHEN ta.score_category = 'Medium' AND ta.trending_status = 'Moderate Trend' THEN 'Solid Performer'
            ELSE 'Regular Post'
        END as performance_label,
        DATE_PART('year', ta.CreationDate) as post_year,
        CASE 
            WHEN ta.Score < 0 THEN 'Negative'
            WHEN ta.Score = 0 THEN 'Zero'
            WHEN ta.Score BETWEEN 1 AND 10 THEN 'Low Positive'
            WHEN ta.Score BETWEEN 11 AND 100 THEN 'Moderate Positive'
            ELSE 'High Positive'
        END as score_range_label,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ta.Id) as comment_count_real,
        COALESCE((SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = ta.Id AND v.VoteTypeId IN (1, 2, 3)), ta.CreationDate) as last_activity_date
    FROM TagAnalysis ta
),
FinalResult AS (
    SELECT 
        cp.*,
        (cp.Score + cp.ViewCount + cp.FavoriteCount) as total_engagement,
        CASE 
            WHEN cp.CommentCount IS NULL THEN 0
            ELSE cp.CommentCount
        END as normalized_comment_count,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = cp.OwnerUserId AND b.Date >= cp.CreationDate) as badges_since_post,
        CASE 
            WHEN cp.Score > 0 AND cp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'AboveAvg'
            WHEN cp.Score > 0 AND cp.Score <= (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'BelowAvg'
            ELSE 'NoScore'
        END as score_performance,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = cp.Id AND v.VoteTypeId = 2) as upvote_count,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = cp.Id AND v.VoteTypeId = 3) as downvote_count,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = cp.Id AND ph.PostHistoryTypeId IN (10, 11, 12, 13)) as history_actions,
        CASE 
            WHEN cp.Tags IS NOT NULL AND cp.Tags != '' THEN 
                (SELECT SUM(COUNT(*)) FROM unnest(cp.tag_array) AS tag GROUP BY tag)
            ELSE NULL
        END as total_tag_frequency
    FROM ComplexCalculations cp
    WHERE cp.PostTypeId = 1
)
SELECT 
    fr.Id,
    fr.Title,
    fr.OwnerUserId,
    fr.Score,
    fr.ViewCount,
    fr.CommentCount,
    fr.FavoriteCount,
    fr.total_engagement,
    fr.score_category,
    fr.trending_status,
    fr.performance_label,
    fr.score_performance,
    fr.post_year,
    fr.weighted_growth,
    fr.engagement_score,
    fr.upvote_count,
    fr.downvote_count,
    fr.last_activity_date,
    fr badges_since_post,
    fr.history_actions,
    COALESCE(fr.total_tag_frequency, 0) as tag_frequency,
    (SELECT STRING_AGG(tag, ', ') FROM unnest(fr.tag_array) AS tag) as tag_list
FROM FinalResult fr
WHERE fr.total_engagement > 100
HAVING COUNT(*) > 0
ORDER BY fr.total_engagement DESC
LIMIT 100;