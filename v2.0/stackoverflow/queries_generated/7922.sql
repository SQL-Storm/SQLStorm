-- {"query": "7922.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2635} 
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
        p.LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as total_posts_by_user,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as avg_score_by_user,
        NTILE(4) OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score) as quartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= '2022-01-01 00:00:00'
),
UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as total_posts,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) as question_count,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) as answer_count,
        COALESCE(SUM(p.Score), 0) as total_score,
        AVG(p.Score) as avg_score,
        MAX(p.CreationDate) as last_post_date,
        STRING_AGG(DISTINCT p.Tags, ', ') as all_tags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= '2022-01-01 00:00:00'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE WHEN t.Count > 100 THEN 'Popular' 
             WHEN t.Count > 10 THEN 'Moderate' 
             ELSE 'Rare' END as tag_category,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) - t.Count as count_diff_from_prev,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) as rank_by_count
    FROM Tags t
    WHERE t.Count > 0
),
PostActivity AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.UserId,
        ph.CreationDate,
        ph.Comment,
        ph.Text,
        CASE 
            WHEN ph.PostHistoryTypeId IN (1, 4, 6) THEN 'Title/Tag Edit'
            WHEN ph.PostHistoryTypeId IN (2, 5) THEN 'Body Edit'
            WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN 'Status Change'
            ELSE 'Other'
        END as activity_type,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate ASC) as activity_sequence
    FROM PostHistory ph
    WHERE ph.CreationDate >= '2023-01-01 00:00:00'
      AND ph.PostHistoryTypeId IN (1, 2, 4, 5, 6, 10, 11, 12, 13)
),
AnswerQuality AS (
    SELECT 
        a.Id as answer_id,
        a.ParentId as question_id,
        a.OwnerUserId,
        a.Score as answer_score,
        a.LastActivityDate,
        q.Score as question_score,
        a.Score - LAG(a.Score) OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate) as score_change,
        CASE 
            WHEN a.Score >= 10 THEN 'High Quality'
            WHEN a.Score >= 5 THEN 'Medium Quality' 
            ELSE 'Low Quality'
        END as quality_level,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) as rank_in_question,
        COUNT(*) OVER (PARTITION BY a.ParentId) as total_answers_in_question
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2 AND q.PostTypeId = 1
),
CombinedAnalysis AS (
    SELECT 
        rp.Id as post_id,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.Score as post_score,
        rp.ViewCount,
        rp.CreationDate,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.LastActivityDate,
        rp.prev_score,
        rp.total_posts_by_user,
        rp.avg_score_by_user,
        rp.quartile,
        us.DisplayName as author_name,
        us.Reputation as author_reputation,
        us.total_posts as author_total_posts,
        us.question_count as author_questions,
        us.answer_count as author_answers,
        us.total_score as author_total_score,
        us.avg_score as author_avg_score,
        us.last_post_date as author_last_post,
        ta.TagName as primary_tag,
        ta.Count as tag_count,
        ta.tag_category,
        pa.activity_type,
        pa.activity_sequence,
        aq.quality_level,
        aq.rank_in_question,
        aq.total_answers_in_question
    FROM RankedPosts rp
    LEFT JOIN UserStats us ON rp.OwnerUserId = us.Id
    LEFT JOIN PostActivity pa ON rp.Id = pa.PostId
    LEFT JOIN Tags ta ON rp.Tags LIKE '%' || ta.TagName || '%'
    LEFT JOIN AnswerQuality aq ON rp.Id = aq.answer_id
    WHERE rp.rn <= 5
),
FinalAggregation AS (
    SELECT 
        ca.post_id,
        ca.PostTypeId,
        ca.OwnerUserId,
        ca.post_score,
        ca.ViewCount,
        ca.CreationDate,
        ca.Title,
        ca.Tags,
        ca.AnswerCount,
        ca.CommentCount,
        ca.FavoriteCount,
        ca.LastActivityDate,
        ca.prev_score,
        ca.total_posts_by_user,
        ca.avg_score_by_user,
        ca.quartile,
        ca.author_name,
        ca.author_reputation,
        ca.author_total_posts,
        ca.author_questions,
        ca.author_answers,
        ca.author_total_score,
        ca.author_avg_score,
        ca.author_last_post,
        ca.primary_tag,
        ca.tag_count,
        ca.tag_category,
        ca.activity_type,
        ca.activity_sequence,
        ca.quality_level,
        ca.rank_in_question,
        ca.total_answers_in_question,
        CASE 
            WHEN ca.post_score > (SELECT AVG(post_score) FROM CombinedAnalysis) THEN 'Above Average'
            WHEN ca.post_score > (SELECT AVG(post_score) * 0.75 FROM CombinedAnalysis) THEN 'Average'
            WHEN ca.post_score > (SELECT AVG(post_score) * 0.5 FROM CombinedAnalysis) THEN 'Below Average'
            ELSE 'Poor'
        END as performance_category,
        COALESCE(NULLIF(ca.author_reputation, 0) / NULLIF(ca.author_total_posts, 0), 0) as rep_per_post,
        (ca.Author_total_score - COALESCE(ca.prev_score, 0)) as score_improvement,
        DATEDIFF('day', ca.CreationDate, ca.LastActivityDate) as days_since_creation,
        CASE 
            WHEN ca.Author_total_posts > 50 AND ca.author_avg_score > 10 AND ca.total_posts_by_user > 10
            THEN 'Highly Active Contributor'
            WHEN ca.author_avg_score > 5 AND ca.total_posts_by_user > 5
            THEN 'Active Contributor'
            ELSE 'Regular Contributor'
        END as contributor_status,
        COALESCE(STRING_AGG(DISTINCT ca.activity_type, ' | '), 'No Activity') as activity_summary,
        COUNT(*) OVER () as total_records,
        ROW_NUMBER() OVER (ORDER BY ca.post_score DESC, ca.LastActivityDate DESC) as row_number_of_post
    FROM CombinedAnalysis ca
    GROUP BY 
        ca.post_id, ca.PostTypeId, ca.OwnerUserId, ca.post_score, ca.ViewCount, ca.CreationDate, 
        ca.Title, ca.Tags, ca.AnswerCount, ca.CommentCount, ca.FavoriteCount, ca.LastActivityDate, 
        ca.prev_score, ca.total_posts_by_user, ca.avg_score_by_user, ca.quartile, ca.author_name, 
        ca.author_reputation, ca.author_total_posts, ca.author_questions, ca.author_answers, 
        ca.author_total_score, ca.author_avg_score, ca.author_last_post, ca.primary_tag, 
        ca.tag_count, ca.tag_category, ca.activity_type, ca.activity_sequence, ca.quality_level, 
        ca.rank_in_question, ca.total_answers_in_question
)
SELECT 
    fa.post_id,
    fa.PostTypeId,
    fa.OwnerUserId,
    fa.post_score,
    fa.ViewCount,
    fa.CreationDate,
    fa.Title,
    fa.Tags,
    fa.AnswerCount,
    fa.CommentCount,
    fa.FavoriteCount,
    fa.LastActivityDate,
    fa.performance_category,
    fa.rep_per_post,
    fa.score_improvement,
    fa.days_since_creation,
    fa.contributor_status,
    fa.activity_summary,
    fa.total_records,
    fa.row_number_of_post,
    CASE 
        WHEN fa.total_records > 1000 THEN 'Large Dataset'
        WHEN fa.total_records > 500 THEN 'Medium Dataset'
        WHEN fa.total_records > 100 THEN 'Small Dataset'
        ELSE 'Tiny Dataset'
    END as dataset_size,
    CAST(100.0 * ROW_NUMBER() OVER (ORDER BY fa.post_score DESC) / COUNT(*) OVER () AS DECIMAL(5,2)) as percentile_rank,
    CASE 
        WHEN fa.post_score > (SELECT AVG(post_score) FROM FinalAggregation) 
        AND fa.avg_score_by_user > (SELECT AVG(avg_score_by_user) FROM FinalAggregation)
        AND fa.contributor_status = 'Highly Active Contributor'
        AND fa.days_since_creation < 90
        THEN 'Top Performer'
        ELSE 'Standard Performer'
    END as performance_rating,
    CASE 
        WHEN fa.Activity_Summary LIKE '%Title/Tag Edit%' 
        AND fa.Activity_Summary LIKE '%Body Edit%'
        THEN 'Well Maintained'
        WHEN fa.Activity_Summary LIKE '%Status Change%'
        THEN 'Moderated Post'
        ELSE 'Standard Post'
    END as post_maintenance_status,
    CASE 
        WHEN fa.Author_Rep > 10000 AND fa.Author_Total_Score > 5000
        THEN 'Elite User'
        WHEN fa.Author_Rep > 1000 AND fa.Author_Total_Score > 1000
        THEN 'Experienced User'
        ELSE 'New User'
    END as user_level_type,
    REVERSE(SUBSTRING(REVERSE(fa.Title), 1, 30)) as reverse_title,
    CONCAT('Post-', CAST(fa.post_id AS VARCHAR(20))) as formatted_post_id,
    EXTRACT(YEAR FROM fa.CreationDate) as creation_year,
    EXTRACT(MONTH FROM fa.CreationDate) as creation_month,
    EXTRACT(DAY FROM fa.CreationDate) as creation_day,
    UPPER(LEFT(fa.primary_tag, 1)) || LOWER(SUBSTRING(fa.primary_tag, 2)) as formatted_tag
FROM FinalAggregation fa
WHERE fa.post_score > 0
  AND fa.Author_Total_Posts > 0
  AND (fa.contributor_status = 'Highly Active Contributor' OR fa.performance_category IN ('Above Average', 'Average'))
  AND fa.LastActivityDate >= '2023-01-01 00:00:00'
  AND (fa.Tags IS NOT NULL AND LENGTH(fa.Tags) > 0)
QUALIFY ROW_NUMBER() OVER (PARTITION BY fa.OwnerUserId ORDER BY fa.post_score DESC) <= 10
ORDER BY fa.post_score DESC, fa.ViewCount DESC, fa.LastActivityDate DESC
LIMIT 1000 OFFSET 0;