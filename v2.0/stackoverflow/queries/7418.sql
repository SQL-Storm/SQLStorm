-- {"query": "7418.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2248}
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
        p.LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as rolling_avg_score,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                COALESCE(
                    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id),
                    0
                )
            ELSE 0 
        END as comment_count_with_null_check,
        CASE 
            WHEN p.PostTypeId = 2 THEN 
                (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2)
            ELSE 0 
        END as answer_count_with_null_check,
        COALESCE(p.Tags, 'No Tags') as safe_tags,
        CASE 
            WHEN p.ViewCount IS NULL OR p.ViewCount < 0 THEN 'Invalid Views'
            WHEN p.ViewCount > 100000 THEN 'High Traffic'
            WHEN p.ViewCount > 10000 THEN 'Medium Traffic'
            ELSE 'Low Traffic'
        END as traffic_category
    FROM Posts p
    WHERE p.CreationDate >= (
            -- normalize to a timestamp comparison in a dialect-independent way
            CAST('2024-10-01' AS timestamp) - INTERVAL '12 months'
        )
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate,
        COUNT(DISTINCT r.PostTypeId) as unique_post_types,
        COUNT(r.Id) as total_posts,
        AVG(r.Score) as avg_score,
        MAX(r.CreationDate) as last_post_date,
        COUNT(DISTINCT CASE WHEN r.PostTypeId = 1 THEN r.Id END) as question_count,
        COUNT(DISTINCT CASE WHEN r.PostTypeId = 2 THEN r.Id END) as answer_count
    FROM Users u
    LEFT JOIN RankedPosts r ON u.Id = r.OwnerUserId
    WHERE u.CreationDate >= (
            CAST('2024-10-01' AS timestamp) - INTERVAL '2 years'
        )
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
ComplexAnalysis AS (
    SELECT 
        ra.Id,
        ra.PostTypeId,
        ra.Score,
        ra.ViewCount,
        ra.CreationDate,
        ra.OwnerUserId,
        ra.Title,
        ra.Tags,
        ra.AnswerCount,
        ra.CommentCount,
        ra.FavoriteCount,
        ra.ClosedDate,
        ra.LastActivityDate,
        ra.rn,
        ra.prev_score,
        ra.rolling_avg_score,
        ra.comment_count_with_null_check,
        ra.answer_count_with_null_check,
        ra.safe_tags,
        ra.traffic_category,
        CASE 
            WHEN ra.Score > (SELECT AVG(Score) FROM RankedPosts) 
                AND ra.ViewCount > (SELECT AVG(ViewCount) FROM RankedPosts) 
                AND ra.AnswerCount > (SELECT AVG(AnswerCount) FROM RankedPosts)
            THEN 'High Performing'
            WHEN ra.Score < (SELECT AVG(Score) FROM RankedPosts) 
                AND ra.ViewCount < (SELECT AVG(ViewCount) FROM RankedPosts) 
                AND ra.AnswerCount < (SELECT AVG(AnswerCount) FROM RankedPosts)
            THEN 'Low Performing'
            ELSE 'Average Performing'
        END as performance_category,
        CASE 
            WHEN ra.Tags LIKE '%sql%' OR ra.Tags LIKE '%database%' OR ra.Tags LIKE '%query%'
            THEN 'Technical Focus'
            WHEN ra.Tags LIKE '%python%' OR ra.Tags LIKE '%programming%' OR ra.Tags LIKE '%coding%'
            THEN 'Programming Focus'
            ELSE 'General'
        END as tag_focus,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - ra.CreationDate)) / 86400.0 as days_since_creation,
        CASE 
            WHEN ra.LastActivityDate IS NULL THEN 'Never Active'
            WHEN EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - ra.LastActivityDate)) / 86400.0 <= 7 THEN 'Recently Active'
            WHEN EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - ra.LastActivityDate)) / 86400.0 <= 30 THEN 'Active Recently'
            ELSE 'Inactive'
        END as activity_status,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ra.Id AND v.VoteTypeId IN (2,3)),
            0
        ) as vote_count,
        CASE 
            WHEN ra.Score > (SELECT AVG(Score) FROM RankedPosts) 
                 AND ra.ViewCount > (SELECT AVG(ViewCount) FROM RankedPosts) 
                 AND ra.AnswerCount > 0
            THEN 'Potential Popular'
            ELSE 'Not Popular'
        END as popularity_flag
    FROM RankedPosts ra
    LEFT JOIN Users u ON ra.OwnerUserId = u.Id
    LEFT JOIN PostHistory ph ON ra.Id = ph.PostId AND ph.PostHistoryTypeId = 10
    WHERE ra.rn <= 5
),
FinalReport AS (
    SELECT 
        ca.Id,
        ca.PostTypeId,
        ca.Score,
        ca.ViewCount,
        ca.OwnerUserId,
        ca.Title,
        ca.Tags,
        ca.AnswerCount,
        ca.CommentCount,
        ca.FavoriteCount,
        ca.ClosedDate,
        ca.LastActivityDate,
        ca.rn,
        ca.prev_score,
        ca.rolling_avg_score,
        ca.comment_count_with_null_check,
        ca.answer_count_with_null_check,
        ca.safe_tags,
        ca.traffic_category,
        ca.performance_category,
        ca.tag_focus,
        ca.days_since_creation,
        ca.activity_status,
        ca.vote_count,
        ca.popularity_flag,
        CASE 
            WHEN ca.rolling_avg_score > 10 THEN 'High Average Score'
            WHEN ca.rolling_avg_score > 5 THEN 'Medium Average Score'
            WHEN ca.rolling_avg_score > 0 THEN 'Low Average Score'
            ELSE 'No Score'
        END as rolling_score_category,
        ROW_NUMBER() OVER (ORDER BY ca.Score * ca.ViewCount DESC) as performance_rank,
        RANK() OVER (PARTITION BY ca.OwnerUserId ORDER BY ca.Score DESC) as user_performance_rank,
        DENSE_RANK() OVER (ORDER BY ca.AnswerCount DESC) as answer_rank,
        NTILE(4) OVER (ORDER BY ca.ViewCount) as view_quartile,
        PERCENT_RANK() OVER (ORDER BY ca.Score) as score_percentile
    FROM ComplexAnalysis ca
    WHERE ca.Id IS NOT NULL
)
SELECT 
    fr.Id,
    fr.PostTypeId,
    fr.Score,
    fr.ViewCount,
    fr.OwnerUserId,
    fr.Title,
    fr.Tags,
    fr.AnswerCount,
    fr.CommentCount,
    fr.FavoriteCount,
    fr.ClosedDate,
    fr.LastActivityDate,
    fr.rn,
    fr.prev_score,
    fr.rolling_avg_score,
    fr.comment_count_with_null_check,
    fr.answer_count_with_null_check,
    fr.safe_tags,
    fr.traffic_category,
    fr.performance_category,
    fr.tag_focus,
    fr.days_since_creation,
    fr.activity_status,
    fr.vote_count,
    fr.popularity_flag,
    fr.rolling_score_category,
    fr.performance_rank,
    fr.user_performance_rank,
    fr.answer_rank,
    fr.view_quartile,
    fr.score_percentile,
    CASE 
        WHEN fr.performance_rank <= 100 THEN 'Top 100'
        WHEN fr.performance_rank <= 500 THEN 'Top 500'
        WHEN fr.performance_rank <= 1000 THEN 'Top 1000'
        ELSE 'Below Top 1000'
    END as rank_category,
    CASE 
        WHEN fr.score_percentile >= 0.9 THEN 'Top 10%'
        WHEN fr.score_percentile >= 0.75 THEN 'Top 25%'
        WHEN fr.score_percentile >= 0.5 THEN 'Top 50%'
        ELSE 'Below 50%'
    END as percentile_category,
    REPLACE(fr.Title, ' ', '_') as title_underscore,
    CHAR_LENGTH(fr.Tags) as tag_length,
    CASE 
        WHEN fr.Score > 0 THEN 
            CAST((fr.ViewCount * 100.0 / NULLIF(fr.Score, 0)) AS NUMERIC(18,2))
        ELSE 0
    END as view_to_score_ratio,
    CASE 
        WHEN fr.AnswerCount > 0 THEN 
            CAST((fr.CommentCount * 100.0 / NULLIF(fr.AnswerCount, 0)) AS NUMERIC(18,2))
        ELSE 0
    END as comment_to_answer_ratio,
    (fr.Score + fr.ViewCount + fr.AnswerCount + fr.CommentCount + fr.FavoriteCount) as total_activity_score,
    CASE 
        WHEN fr.ViewCount > 1000 THEN 
            (SELECT DisplayName FROM Users WHERE Id = fr.OwnerUserId LIMIT 1)
        ELSE NULL
    END as author_display_name,
    CASE 
        WHEN EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = fr.Id AND ph.PostHistoryTypeId = 10)
            THEN 'Closed'
        WHEN fr.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END as post_status,
    CASE 
        WHEN fr.LastActivityDate IS NULL THEN 'Never Active'
        WHEN EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - fr.LastActivityDate)) / 86400.0 = 0 THEN 'Today'
        WHEN EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - fr.LastActivityDate)) / 86400.0 = 1 THEN 'Yesterday'
        ELSE CAST( FLOOR( EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - fr.LastActivityDate)) / 86400.0 ) AS text ) || ' days ago'
    END as last_activity_desc
FROM FinalReport fr
WHERE fr.Id IS NOT NULL
    AND fr.ViewCount IS NOT NULL
    AND fr.Score IS NOT NULL
    AND (fr.Score > 0 OR fr.ViewCount > 0 OR fr.AnswerCount > 0)
    AND (fr.OwnerUserId IS NOT NULL OR fr.OwnerUserId = -1)
ORDER BY fr.performance_rank ASC, fr.view_quartile ASC, fr.user_performance_rank ASC;