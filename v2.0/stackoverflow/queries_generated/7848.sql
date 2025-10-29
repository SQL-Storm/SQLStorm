-- {"query": "7848.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2879} 
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
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) as avg_score_5days,
        CASE WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN ARRAY_LENGTH(string_to_array(trim(p.Tags, '<>'), '><'), 1) ELSE 0 END as tag_count,
        CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END as question_answer_count,
        CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END as answer_score,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as score_rank,
        NTILE(10) OVER (ORDER BY p.Score DESC) as score_decile
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01'::timestamp
),
UserActivity AS (
    SELECT 
        u.Id as user_id,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT c.Id) as comment_count,
        COUNT(DISTINCT b.Id) as badge_count,
        MAX(p.CreationDate) as last_post_date,
        MAX(c.CreationDate) as last_comment_date,
        MAX(b.Date) as last_badge_date,
        COALESCE(SUM(p.Score), 0) as total_score,
        COALESCE(SUM(p.ViewCount), 0) as total_views,
        AVG(p.Score) as avg_post_score,
        CASE WHEN COUNT(DISTINCT p.Id) > 0 THEN COUNT(DISTINCT p.Id) * 100.0 / (COUNT(DISTINCT p.Id) + COUNT(DISTINCT c.Id)) ELSE 0 END as post_to_comment_ratio
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2019-01-01'::timestamp
    GROUP BY u.Id, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
TagAnalysis AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE WHEN t.IsRequired = 1 THEN 'Required' ELSE 'Optional' END as tag_type,
        CASE WHEN t.Count > 1000 THEN 'Popular' WHEN t.Count > 100 THEN 'Moderate' ELSE 'Rare' END as tag_popularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as popularity_rank,
        PERCENT_RANK() OVER (ORDER BY t.Count) as popularity_percentile,
        AVG(t.Count) OVER () as avg_tag_count,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) as prev_count
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND t.TagName != ''
),
PostPerformance AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.rn,
        rp.prev_score,
        rp.avg_score_5days,
        rp.tag_count,
        rp.question_answer_count,
        rp.answer_score,
        rp.score_rank,
        rp.score_decile,
        CASE WHEN rp.prev_score IS NOT NULL THEN rp.Score - rp.prev_score ELSE 0 END as score_change,
        CASE WHEN rp.avg_score_5days > 0 THEN (rp.Score - rp.avg_score_5days) * 100.0 / rp.avg_score_5days ELSE 0 END as score_deviation_pct,
        CASE WHEN rp.score_rank <= 100 THEN 'Top 100' WHEN rp.score_rank <= 500 THEN 'Top 500' ELSE 'Below Top 500' END as rank_category,
        CASE WHEN rp.Score < 0 THEN 'Negative' WHEN rp.Score BETWEEN 0 AND 5 THEN 'Low' WHEN rp.Score BETWEEN 6 AND 20 THEN 'Medium' WHEN rp.Score BETWEEN 21 AND 100 THEN 'High' ELSE 'Very High' END as score_category,
        CASE WHEN rp.Score > (SELECT AVG(Score) FROM Posts) THEN 1 ELSE 0 END as above_avg_score
    FROM RankedPosts rp
    WHERE rp.rn <= 10
),
AggregateStats AS (
    SELECT 
        COUNT(*) as total_posts,
        COUNT(DISTINCT OwnerUserId) as unique_authors,
        AVG(Score) as avg_score,
        AVG(ViewCount) as avg_views,
        MAX(CreationDate) as latest_post,
        MIN(CreationDate) as earliest_post,
        COUNT(CASE WHEN PostTypeId = 1 THEN 1 END) as question_count,
        COUNT(CASE WHEN PostTypeId = 2 THEN 1 END) as answer_count,
        AVG(CommentCount) as avg_comments,
        AVG(FavoriteCount) as avg_favorites
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01'::timestamp
),
ComplexAnalytics AS (
    SELECT 
        pa.Id,
        pa.PostTypeId,
        pa.OwnerUserId,
        pa.Score,
        pa.SScore,
        pa.ViewCount,
        pa.CreationDate,
        pa.Title,
        pa.Tags,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.rn,
        pa.prev_score,
        pa.avg_score_5days,
        pa.tag_count,
        pa.question_answer_count,
        pa.answer_score,
        pa.score_rank,
        pa.score_decile,
        pa.score_change,
        pa.score_deviation_pct,
        pa.rank_category,
        pa.score_category,
        pa.above_avg_score,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        ua.post_count,
        ua.comment_count,
        ua.badge_count,
        ua.total_score,
        CASE WHEN pa.Score > 100 AND pa.ViewCount > 1000 THEN 1 ELSE 0 END as high_impact_post,
        CASE WHEN pa.score_change > 50 THEN 'High Growth' 
             WHEN pa.score_change > 10 THEN 'Moderate Growth' 
             WHEN pa.score_change > 0 THEN 'Low Growth' 
             ELSE 'Decline' END as performance_trend,
        CASE WHEN pa.score_deviation_pct > 50 THEN 'Significant Deviation' 
             WHEN pa.score_deviation_pct > 10 THEN 'Moderate Deviation' 
             ELSE 'Stable' END as deviation_status,
        LAG(pa.Score) OVER (ORDER BY pa.CreationDate) - pa.Score as prev_score_diff,
        LEAD(pa.Score) OVER (ORDER BY pa.CreationDate) - pa.Score as next_score_diff,
        NTILE(5) OVER (ORDER BY pa.Score DESC) as score_quintile,
        PERCENT_RANK() OVER (ORDER BY pa.Score) as score_percentile,
        DENSE_RANK() OVER (ORDER BY pa.ViewCount DESC) as view_rank,
        CASE WHEN pa.answer_score > 10 THEN 'Highly Upvoted Answer' 
             WHEN pa.answer_score > 5 THEN 'Moderately Upvoted Answer' 
             ELSE 'Low Upvoted Answer' END as answer_quality,
        CASE WHEN pa.TagName LIKE '%sql%' OR pa.TagName LIKE '%database%' THEN 'Database Focus' 
             WHEN pa.TagName LIKE '%python%' OR pa.TagName LIKE '%programming%' THEN 'Programming Focus' 
             ELSE 'General' END as content_domain
    FROM PostPerformance pa
    JOIN Users u ON pa.OwnerUserId = u.Id
    JOIN UserActivity ua ON pa.OwnerUserId = ua.user_id
    WHERE pa.Score > 0 AND pa.ViewCount > 0
)
SELECT 
    CONCAT(
        'Analysis for post ', 
        ca.Id, 
        ' by user ', 
        ca.OwnerUserId, 
        ' - Score: ', 
        ca.Score, 
        ', Views: ', 
        ca.ViewCount,
        ', Creation: ', 
        TO_CHAR(ca.CreationDate, 'YYYY-MM-DD'),
        ', Tag Count: ', 
        ca.tag_count,
        ', Rank: ', 
        ca.score_rank,
        ', Category: ', 
        ca.rank_category,
        CASE WHEN ca.above_avg_score = 1 THEN ' (Above Avg)' ELSE '' END
    ) as detailed_analysis,
    ca.PostTypeId,
    ca.Title,
    ca.Tags,
    ca.AnswerCount,
    ca.CommentCount,
    ca.FavoriteCount,
    ca.Reputation,
    ca.post_count,
    ca.comment_count,
    ca.badge_count,
    ca.total_score,
    ca.performance_trend,
    ca.deviation_status,
    ca.score_percentile,
    ca.view_rank,
    ca.answer_quality,
    CASE WHEN EXISTS (SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = ca.OwnerUserId AND p2.PostTypeId = 1 AND p2.CreationDate > ca.CreationDate) THEN 'Has Previous Questions' ELSE 'No Previous Questions' END as user_question_history,
    CASE WHEN (ca.Score_change > 0) AND (ca.score_deviation_pct > 20) THEN 'Rising Star' 
         WHEN (ca.Score_change < 0) AND (ca.score_deviation_pct < -20) THEN 'Falling Star' 
         WHEN ca.Score > 100 AND ca.ViewCount > 1000 THEN 'Popular Contributor' 
         ELSE 'Regular Participant' END as contributor_status,
    (SELECT COUNT(*) FROM Tags t WHERE t.TagName IN (SELECT unnest(string_to_array(trim(ca.Tags, '<>'), '><')))) as tag_matches,
    (SELECT AVG(Count) FROM Tags WHERE TagName IN (SELECT unnest(string_to_array(trim(ca.Tags, '<>'), '><')))) as avg_tag_popularity,
    (SELECT STRING_AGG(TagName, ', ') FROM Tags WHERE TagName IN (SELECT unnest(string_to_array(trim(ca.Tags, '<>'), '><')))) as matching_tags,
    CASE 
        WHEN CHAR_LENGTH(ca.Title) > 100 THEN 'Long Title'
        WHEN CHAR_LENGTH(ca.Title) > 50 THEN 'Medium Title'
        WHEN CHAR_LENGTH(ca.Title) > 20 THEN 'Short Title'
        ELSE 'Very Short Title'
    END as title_length_category,
    CASE 
        WHEN ca.ViewCount > 5000 THEN 'Viral'
        WHEN ca.ViewCount > 1000 THEN 'Popular'
        WHEN ca.ViewCount > 500 THEN 'Moderate'
        ELSE 'Low'
    END as view_category,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ca.OwnerUserId AND p.CreationDate >= '2023-01-01'::timestamp AND p.CreationDate <= '2023-12-31'::timestamp) as recent_post_count,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.ParentId = ca.Id AND p.PostTypeId = 2 AND p.Score > 50) THEN 'High Quality Thread'
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.ParentId = ca.Id AND p.PostTypeId = 2 AND p.Score > 10) THEN 'Moderate Thread'
        ELSE 'Low Thread Quality'
    END as thread_quality,
    (SELECT MAX(CreationDate) FROM Posts p WHERE p.OwnerUserId = ca.OwnerUserId) as user_last_activity,
    (SELECT STRING_AGG(v.Name, ', ') FROM Votes v INNER JOIN Posts p ON v.PostId = p.Id WHERE p.Id = ca.Id AND v.VoteTypeId = 2) as upvoter_names,
    EXISTS (
        SELECT 1 FROM Posts p 
        INNER JOIN PostLinks pl ON p.Id = pl.PostId 
        WHERE p.Id = ca.Id 
        AND pl.LinkTypeId = 3
    ) as marked_duplicate,
    (
        SELECT COUNT(*) FROM Posts p 
        INNER JOIN PostLink pl ON p.Id = pl.RelatedPostId 
        WHERE pl.PostId = ca.Id
    ) as cross_reference_count
FROM ComplexAnalytics ca
LEFT JOIN Users u ON ca.OwnerUserId = u.Id
LEFT JOIN PostHistory ph ON ca.Id = ph.PostId AND ph.PostHistoryTypeId IN (1, 2, 3)
WHERE ca.Score > 50
  AND ca.ViewCount > 50
  AND ca.post_count > 0
  AND ca.total_score > 100
  AND (ca.score_change IS NULL OR ca.score_change != 0)
ORDER BY ca.Score DESC, ca.ViewCount DESC, ca.CreationDate DESC
LIMIT 100;