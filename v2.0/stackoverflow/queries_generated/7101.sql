-- {"query": "7101.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1992} 
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
        LAG(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_views,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as avg_score,
        NTILE(4) OVER (ORDER BY p.Score) as score_quartile,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                ARRAY_LENGTH(string_to_array(trim(trim(p.Tags, '<>'), '><'), '><')) 
            ELSE 0 
        END as tag_count
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= '2020-01-01'
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT p.Id) as total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answers,
        COALESCE(SUM(p.Score), 0) as total_score,
        AVG(p.Score) as avg_score,
        MAX(p.CreationDate) as latest_activity,
        STRING_AGG(DISTINCT p.Tags, '; ') as all_tags_used
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= '2015-01-01'
    GROUP BY u.Id, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE WHEN t.IsRequired = 1 THEN 'Required' ELSE 'Optional' END as tag_type,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) as popularity_rank,
        PERCENT_RANK() OVER (ORDER BY t.Count) as popularity_percentile
    FROM Tags t
    WHERE t.Count > 100
),
PostsWithHistory AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Comment,
        ph.Text,
        ph.RevisionGUID,
        COALESCE(ph.Text, '') as history_text,
        COALESCE(ph.Comment, '') as history_comment,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) as recent_history
    FROM PostHistory ph
    WHERE ph.CreationDate >= '2021-01-01'
      AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
),
AnswerStats AS (
    SELECT 
        p.ParentId as QuestionId,
        COUNT(*) as answer_count,
        SUM(p.Score) as total_answer_score,
        AVG(p.Score) as avg_answer_score,
        MAX(p.Score) as max_answer_score,
        MIN(p.Score) as min_answer_score,
        COUNT(CASE WHEN p.Score > 0 THEN 1 END) as positive_answers,
        COUNT(CASE WHEN p.Score < 0 THEN 1 END) as negative_answers,
        COUNT(CASE WHEN p.Score = 0 THEN 1 END) as zero_score_answers,
        STRING_AGG(p.Title, '; ') as answer_titles,
        STRING_AGG(CAST(p.Score AS VARCHAR), ', ') as score_list
    FROM Posts p
    WHERE p.PostTypeId = 2
      AND p.ParentId IS NOT NULL
    GROUP BY p.ParentId
)
SELECT 
    'Performance Benchmarked Query Results' as report_title,
    COUNT(*) as total_records,
    COUNT(DISTINCT r.Id) as distinct_posts,
    COUNT(DISTINCT u.Id) as distinct_users,
    COUNT(DISTINCT t.TagName) as distinct_tags,
    COUNT(DISTINCT CASE WHEN r.PostTypeId = 1 THEN r.Id END) as question_count,
    COUNT(DISTINCT CASE WHEN r.PostTypeId = 2 THEN r.Id END) as answer_count,
    ROUND(AVG(r.Score), 2) as overall_avg_score,
    ROUND(AVG(u.Reputation), 0) as avg_user_reputation,
    MAX(r.CreationDate) as latest_post_date,
    MIN(r.CreationDate) as earliest_post_date,
    
    -- Complex calculations for performance testing
    ROUND(
        AVG(
            CASE 
                WHEN r.prev_score IS NOT NULL THEN 
                    (r.Score - COALESCE(r.prev_score, 0)) * 
                    GREATEST(1, (r.prev_views / NULLIF(r.ViewCount, 0))::numeric)
                ELSE 0 
            END
        ), 2
    ) as avg_score_change_factor,
    
    -- String manipulations and concatenations
    STRING_AGG(
        CASE 
            WHEN r.Title IS NOT NULL AND r.Tags IS NOT NULL THEN 
                SUBSTRING(r.Title, 1, 30) || ' (' || 
                COALESCE(SUBSTRING(r.Tags, 2, LENGTH(r.Tags)-2), '') || ')'
            ELSE 'No Title'
        END, 
        ' | '
    ) as formatted_titles,
    
    -- Set operators and complex predicates
    (SELECT COUNT(*) FROM (
        SELECT DISTINCT u.Id FROM Users u
        INNER JOIN Posts p ON u.Id = p.OwnerUserId
        INNER JOIN PostHistory ph ON p.Id = ph.PostId
        WHERE u.Reputation > 10000
          AND ph.PostHistoryTypeId IN (1, 2, 3)
          AND ph.CreationDate BETWEEN '2020-01-01' AND '2022-12-31'
        MINUS
        SELECT u.Id FROM Users u
        WHERE u.Views > 50000
    ) t) as complex_set_op_result,
    
    -- Window function with complex expressions
    (SELECT MAX(score_quartile) FROM RankedPosts) as max_quartile,
    (SELECT MIN(r2.Score) FROM RankedPosts r2 WHERE r2.score_quartile = 1) as min_low_quartile_score,
    
    -- Correlated subqueries and NULL handling
    COALESCE(
        (SELECT SUM(p2.Score) 
         FROM Posts p2 
         WHERE p2.OwnerUserId = u.Id 
           AND p2.CreationDate > '2021-01-01'), 
        0
    ) as recent_user_score,
    
    -- Complex string expressions
    CONCAT(
        'Users with ', 
        COUNT(DISTINCT CASE WHEN u.Reputation > 10000 THEN u.Id END),
        ' expert users, ',
        COUNT(DISTINCT CASE WHEN u.Views > 50000 THEN u.Id END),
        ' highly viewed users'
    ) as user_summary,
    
    -- Aggregations with conditional logic
    ROUND(
        AVG(CASE 
            WHEN r.tag_count > 3 THEN r.Score 
            ELSE NULL 
        END), 2
    ) as avg_score_high_tag,
    
    -- Multiple joins and complex logic
    (SELECT COUNT(*) 
     FROM Posts p1 
     LEFT JOIN AnswerStats ans ON p1.Id = ans.QuestionId
     WHERE p1.PostTypeId = 1
       AND ans.answer_count > 10
       AND p1.Score > 50
       AND (p1.Title IS NOT NULL OR p1.Body IS NOT NULL)
    ) as complex_joined_count,
    
    -- NULL-aware calculations
    ROUND(
        COALESCE(
            AVG(r.Score) / NULLIF(AVG(r.ViewCount), 0), 
            0
        ), 4
    ) as score_to_view_ratio
    
FROM RankedPosts r
FULL OUTER JOIN Users u ON r.OwnerUserId = u.Id
LEFT JOIN TagAnalysis t ON u.AccountId IS NOT NULL
LEFT JOIN PostsWithHistory ph ON r.Id = ph.PostId
LEFT JOIN AnswerStats ans ON r.Id = ans.QuestionId
WHERE (r.Score > 5 OR r.ViewCount > 1000 OR u.Reputation > 1000)
  AND (r.CreationDate BETWEEN '2019-01-01' AND '2023-12-31' OR u.CreationDate BETWEEN '2015-01-01' AND '2023-12-31')
  AND (r.Title IS NOT NULL OR r.Body IS NOT NULL OR ph.PostId IS NOT NULL)
HAVING COUNT(*) > 0
ORDER BY r.CreationDate DESC, u.Reputation DESC
LIMIT 1000;