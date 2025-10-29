-- {"query": "7726.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1591} 
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ParentId,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as user_post_count,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END as score_category,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                ARRAY_LENGTH(string_to_array(trim(p.Tags, '<>'), '><'), 1)
            ELSE 0 
        END as tag_count
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
        AND p.CreationDate >= '2020-01-01'
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT r.PostId) as posts_count,
        AVG(r.Score) as avg_score,
        MAX(r.CreationDate) as last_post_date,
        STRING_AGG(DISTINCT r.Tags, '; ') as all_tags
    FROM Users u
    LEFT JOIN RankedPosts r ON u.Id = r.OwnerUserId
    WHERE u.CreationDate >= '2019-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(p.Score, 0) as excerpt_score,
        CASE 
            WHEN t.Count > 100 THEN 'Popular'
            WHEN t.Count > 50 THEN 'Medium'
            ELSE 'Rare'
        END as tag_popularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as popularity_rank
    FROM Tags t
    LEFT JOIN Posts p ON t.ExcerptPostId = p.Id
    WHERE t.Count > 0
),
AnswerStats AS (
    SELECT 
        a.PostId,
        a.Score as answer_score,
        a.CreationDate as answer_date,
        q.Score as question_score,
        q.Title as question_title,
        a.OwnerUserId,
        COALESCE(a.OwnerUserId, a.LastEditorUserId) as effective_user_id,
        DATEDIFF('day', q.CreationDate, a.CreationDate) as days_to_answer,
        CASE 
            WHEN a.Score > q.Score THEN 'Above Question Score'
            WHEN a.Score = q.Score THEN 'Equal to Question Score'
            ELSE 'Below Question Score'
        END as score_comparison
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2 AND a.CreationDate >= '2020-01-01'
),
QualityPosts AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.Score,
        rp.ViewCount,
        rp.Score - COALESCE(rp.prev_score, 0) as score_change,
        rp.tag_count,
        COALESCE(us.avg_score, 0) as user_avg_score,
        CASE 
            WHEN rp.Score > 100 AND rp.ViewCount > 500 THEN 'High Quality'
            WHEN rp.Score > 50 AND rp.ViewCount > 200 THEN 'Medium Quality'
            ELSE 'Low Quality'
        END as quality_level,
        CASE 
            WHEN rp.user_post_count > 10 THEN 'Active Poster'
            WHEN rp.user_post_count > 5 THEN 'Regular Poster'
            ELSE 'Occasional Poster'
        END as posting_frequency
    FROM RankedPosts rp
    LEFT JOIN UserStats us ON rp.OwnerUserId = us.UserId
    WHERE rp.rn = 1
)
SELECT 
    'Performance Benchmark Query Results' as query_info,
    COUNT(*) as total_records,
    COUNT(DISTINCT up.UserId) as unique_users,
    COUNT(DISTINCT ta.TagName) as total_tags,
    COUNT(DISTINCT ap.PostId) as answers_count,
    ROUND(AVG(qp.score_change), 2) as avg_score_change,
    STRING_AGG(
        CONCAT(
            'User:', up.DisplayName, 
            ' | Posts:', up.posts_count,
            ' | Avg Score:', ROUND(up.avg_score, 2),
            ' | Tags:', COALESCE(up.all_tags, 'None')
        ), 
        ' || ' 
    ) as user_summary,
    STRING_AGG(
        CONCAT(
            'Tag:', ta.TagName, 
            ' | Popularity:', ta.tag_popularity,
            ' | Count:', ta.Count
        ), 
        ' || ' 
    ) as tag_summary,
    STRING_AGG(
        CONCAT(
            'Title:', qp.Title, 
            ' | Quality:', qp.quality_level,
            ' | Score:', qp.Score,
            ' | Views:', qp.ViewCount
        ), 
        ' || ' 
    ) as post_summary
FROM UserStats up
FULL OUTER JOIN TagAnalysis ta ON 1=1
FULL OUTER JOIN AnswerStats ap ON 1=1
FULL OUTER JOIN QualityPosts qp ON 1=1
WHERE 
    (up.UserId IS NOT NULL OR ta.TagName IS NOT NULL OR ap.PostId IS NOT NULL OR qp.PostId IS NOT NULL)
    AND (
        up.Reputation > 1000 
        OR ta.Count > 10 
        OR ap.answer_score > 5 
        OR qp.Score > 10
    )
    AND (
        (up.posts_count > 1 OR ap.PostId IS NOT NULL OR qp.PostId IS NOT NULL)
        OR ta.TagName IS NOT NULL
    )
    AND (
        up.last_post_date >= '2020-01-01' 
        OR ap.answer_date >= '2020-01-01'
        OR qp.Score > 0
    )
HAVING 
    COUNT(*) > 0
UNION ALL
SELECT 
    'Additional Performance Metrics',
    COUNT(DISTINCT up.UserId) as total_users,
    SUM(up.posts_count) as total_posts,
    COUNT(DISTINCT ta.TagName) as total_tags,
    COUNT(DISTINCT ap.PostId) as total_answers,
    AVG(qp.score_change) as avg_score_change,
    STRING_AGG(DISTINCT up.DisplayName, ', ') as most_active_users,
    STRING_AGG(DISTINCT ta.TagName, ', ') as most_popular_tags,
    STRING_AGG(DISTINCT qp.Title, ', ') as sample_questions
FROM UserStats up
LEFT JOIN TagAnalysis ta ON 1=1
LEFT JOIN AnswerStats ap ON 1=1
LEFT JOIN QualityPosts qp ON 1=1
WHERE 
    up.Reputation > 500 
    AND ta.Count >= 5 
    AND ap.answer_score >= 3 
    AND qp.Score >= 5
    AND up.last_post_date >= '2021-01-01'
    AND ta.popularity_rank <= 50
ORDER BY 1;