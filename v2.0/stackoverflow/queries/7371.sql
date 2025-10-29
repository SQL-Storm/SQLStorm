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
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS avg_score_3posts,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 10 THEN 'Medium'
            ELSE 'Low'
        END AS score_category,
        COALESCE(p.Title, '') AS title_or_empty,
        ('Post_' || CAST(p.Id AS VARCHAR) || '_by_' || COALESCE(u.DisplayName, 'Unknown')) AS post_identifier
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
        END AS score_growth_pct,
        CASE 
            WHEN rp.avg_score_3posts > 50 THEN 'Consistently High'
            WHEN rp.avg_score_3posts > 10 THEN 'Moderate Trend'
            ELSE 'Low Volume'
        END AS trending_status
    FROM RankedPosts rp
    WHERE rp.rn <= 5
),
TagAnalysis AS (
    SELECT 
        fp.*,
        CASE 
            WHEN fp.Tags IS NOT NULL AND fp.Tags <> '' THEN 
                -- count tags by splitting on '><' after removing leading '<' and trailing '>'
                CARDINALITY(STRING_TO_ARRAY(TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM fp.Tags)), '><'))
            ELSE 0
        END AS tag_count,
        CASE 
            WHEN fp.Tags IS NOT NULL AND fp.Tags <> '' 
            THEN STRING_TO_ARRAY(TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM fp.Tags)), '><')
            ELSE ARRAY[]::TEXT[]
        END AS tag_array,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = fp.Id AND p2.PostTypeId = 2) AS answer_count_corrected
    FROM FilteredPosts fp
),
ComplexCalculations AS (
    SELECT 
        ta.*,
        ta.score_growth_pct * ta.tag_count AS weighted_growth,
        ta.answer_count_corrected * ta.Score AS engagement_score,
        COALESCE(ta.Title, 'No Title') AS final_title,
        CASE 
            WHEN ta.score_category = 'High' AND ta.trending_status = 'Consistently High' THEN 'Star Performer'
            WHEN ta.score_category = 'Medium' AND ta.trending_status = 'Moderate Trend' THEN 'Solid Performer'
            ELSE 'Regular Post'
        END AS performance_label,
        EXTRACT(YEAR FROM ta.CreationDate) AS post_year,
        CASE 
            WHEN ta.Score < 0 THEN 'Negative'
            WHEN ta.Score = 0 THEN 'Zero'
            WHEN ta.Score BETWEEN 1 AND 10 THEN 'Low Positive'
            WHEN ta.Score BETWEEN 11 AND 100 THEN 'Moderate Positive'
            ELSE 'High Positive'
        END AS score_range_label,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ta.Id) AS comment_count_real,
        COALESCE((SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = ta.Id AND v.VoteTypeId IN (1, 2, 3)), ta.CreationDate) AS last_activity_date
    FROM TagAnalysis ta
),
FinalResult AS (
    SELECT 
        cp.*,
        (cp.Score + cp.ViewCount + COALESCE(cp.FavoriteCount,0)) AS total_engagement,
        COALESCE(cp.CommentCount, 0) AS normalized_comment_count,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = cp.OwnerUserId AND b.Date >= cp.CreationDate) AS badges_since_post,
        CASE 
            WHEN cp.Score > 0 AND cp.Score > (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.PostTypeId = 1) THEN 'AboveAvg'
            WHEN cp.Score > 0 AND cp.Score <= (SELECT AVG(p3.Score) FROM Posts p3 WHERE p3.PostTypeId = 1) THEN 'BelowAvg'
            ELSE 'NoScore'
        END AS score_performance,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = cp.Id AND v.VoteTypeId = 2) AS upvote_count,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = cp.Id AND v.VoteTypeId = 3) AS downvote_count,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = cp.Id AND ph.PostHistoryTypeId IN (10, 11, 12, 13)) AS history_actions,
        CASE 
            WHEN cp.Tags IS NOT NULL AND cp.Tags <> '' THEN 
                (SELECT SUM(freq) FROM (
                     SELECT COUNT(*) AS freq
                     FROM UNNEST(cp.tag_array) AS t(tag)
                     GROUP BY tag
                 ) sub)
            ELSE NULL
        END AS total_tag_frequency
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
    fr.badges_since_post,
    fr.history_actions,
    COALESCE(fr.total_tag_frequency, 0) AS tag_frequency,
    (SELECT STRING_AGG(tag, ', ') FROM UNNEST(fr.tag_array) AS t(tag)) AS tag_list,
    fr.rn,
    fr.prev_score,
    fr.avg_score_3posts,
    fr.title_or_empty,
    fr.post_identifier,
    fr.score_growth_pct,
    fr.trending_status AS trending_status_dup,
    fr.tag_count,
    fr.answer_count_corrected,
    fr.final_title,
    fr.performance_label AS performance_label_dup,
    fr.post_year AS post_year_dup,
    fr.score_range_label,
    fr.comment_count_real
FROM FinalResult fr
WHERE fr.total_engagement > 100
GROUP BY
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
    fr.badges_since_post,
    fr.history_actions,
    fr.total_tag_frequency,
    fr.tag_array,
    fr.rn,
    fr.prev_score,
    fr.avg_score_3posts,
    fr.title_or_empty,
    fr.post_identifier,
    fr.score_growth_pct,
    fr.tag_count,
    fr.answer_count_corrected,
    fr.final_title,
    fr.score_range_label,
    fr.comment_count_real
HAVING COUNT(*) > 0
ORDER BY fr.total_engagement DESC
LIMIT 100;