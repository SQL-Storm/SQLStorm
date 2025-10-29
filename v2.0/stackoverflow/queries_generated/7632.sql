-- {"query": "7632.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1975} 
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
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as avg_score,
        NTILE(4) OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score) as score_quartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.Score >= 0
),
UserActivity AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT c.Id) as comment_count,
        COUNT(DISTINCT b.Id) as badge_count,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as question_count,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as answer_count,
        SUM(COALESCE(p.Score, 0)) as total_score,
        MAX(c.CreationDate) as last_comment_date,
        MAX(p.CreationDate) as last_post_date
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        p.Title as excerpt_title,
        p.Body as excerpt_body,
        CASE 
            WHEN p.Body LIKE '%<p>%' AND p.Body LIKE '%</p>%' THEN 
                SUBSTRING(p.Body FROM POSITION('<p>' IN p.Body) + 3 FOR POSITION('</p>' IN p.Body) - POSITION('<p>' IN p.Body) - 3)
            ELSE NULL 
        END as excerpt_text,
        CASE 
            WHEN p.Body IS NOT NULL THEN LENGTH(p.Body)
            ELSE 0 
        END as excerpt_length
    FROM Tags t
    LEFT JOIN Posts p ON t.ExcerptPostId = p.Id
    WHERE t.Count > 100
),
ComplexQuestionAnalysis AS (
    SELECT 
        q.Id as question_id,
        q.Title,
        q.Tags,
        q.Score as question_score,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        q.CreationDate,
        q.OwnerUserId,
        CASE 
            WHEN q.AnswerCount > 0 THEN 
                (SELECT AVG(a.Score) FROM Posts a WHERE a.ParentId = q.Id) 
            ELSE 0 
        END as avg_answer_score,
        CASE 
            WHEN q.AnswerCount > 0 THEN 
                (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = q.Id AND a.Score > 0) 
            ELSE 0 
        END as positive_answers,
        CASE 
            WHEN q.AnswerCount > 0 THEN 
                (SELECT MAX(a.Score) FROM Posts a WHERE a.ParentId = q.Id) 
            ELSE 0 
        END as max_answer_score,
        EXISTS (SELECT 1 FROM Posts a WHERE a.ParentId = q.Id AND a.Score = (SELECT MAX(s) FROM Posts s WHERE s.ParentId = q.Id)) as has_highest_scoring_answer,
        NULLIF(q.Tags, '') as non_null_tags,
        TRIM(q.Title) as trimmed_title,
        LENGTH(q.Title) as title_length,
        COALESCE(q.FavoriteCount, 0) as favorite_count,
        COALESCE(q.AnswerCount, 0) as answer_count,
        COALESCE(q.CommentCount, 0) as comment_count,
        COALESCE(q.ViewCount, 0) as view_count
    FROM Posts q
    WHERE q.PostTypeId = 1 
      AND q.CreationDate >= '2020-01-01'::timestamp
      AND q.Score >= 10
),
QuestionWithStats AS (
    SELECT 
        cqa.*,
        ROW_NUMBER() OVER (ORDER BY cqa.question_score DESC) as score_rank,
        DENSE_RANK() OVER (ORDER BY cqa.question_score DESC) as score_dense_rank,
        NTILE(10) OVER (ORDER BY cqa.question_score DESC) as score_decile,
        CASE 
            WHEN cqa.question_score >= 100 THEN 'High'
            WHEN cqa.question_score >= 50 THEN 'Medium'
            WHEN cqa.question_score >= 10 THEN 'Low'
            ELSE 'Very Low'
        END as score_category,
        RANK() OVER (PARTITION BY LEFT(cqa.Tags, 10) ORDER BY cqa.question_score DESC) as tag_rank,
        CASE 
            WHEN cqa.answer_count > 0 AND cqa.avg_answer_score > 5 THEN 'Highlyrated'
            WHEN cqa.answer_count > 0 AND cqa.avg_answer_score > 0 THEN 'Moderate'
            WHEN cqa.answer_count > 0 THEN 'Low'
            ELSE 'No Answers'
        END as answer_quality,
        (cqa.view_count / NULLIF(cqa.answer_count + 1, 0)) as views_per_answer,
        COALESCE(cqa.favorite_count, 0) * 0.1 + COALESCE(cqa.comment_count, 0) * 0.05 + COALESCE(cqa.answer_count, 0) * 0.2 AS engagement_score
    FROM ComplexQuestionAnalysis cqa
)
SELECT 
    qws.*,
    ua.Reputation,
    ua.Views as user_views,
    ua.post_count,
    ua.question_count,
    ua.answer_count,
    ua.total_score,
    ta.TagName,
    ta.Count as tag_count,
    ta.excerpt_text,
    ta.excerpt_length,
    CASE 
        WHEN qws.views_per_answer > 1000 THEN 'High engagement'
        WHEN qws.views_per_answer > 100 THEN 'Moderate engagement'
        ELSE 'Low engagement'
    END as engagement_level,
    DATEDIFF('days', qws.CreationDate, NOW()) as days_since_post,
    CASE 
        WHEN qws.score_rank <= 10 THEN 'Top 10'
        WHEN qws.score_rank <= 50 THEN 'Top 50'
        WHEN qws.score_rank <= 100 THEN 'Top 100'
        ELSE 'Other'
    END as performance_tier,
    ROW_NUMBER() OVER (ORDER BY qws.engagement_score DESC) as engagement_rank,
    ROUND(qws.engagement_score, 2) as rounded_engagement_score,
    CONCAT(qws.Title, ' - ', qws.TagName) as title_tag_combo,
    CASE 
        WHEN LENGTH(qws.Tags) > 100 THEN 'Long tags'
        WHEN LENGTH(qws.Tags) > 50 THEN 'Medium tags'
        ELSE 'Short tags'
    END as tag_length_category,
    CASE 
        WHEN qws.question_score > (SELECT AVG(question_score) FROM QuestionWithStats) THEN 'Above Average'
        WHEN qws.question_score > (SELECT AVG(question_score) FROM QuestionWithStats) * 0.5 THEN 'Below Average'
        ELSE 'Very Below Average'
    END as score_comparison,
    LAG(qws.question_score, 1) OVER (ORDER BY qws.question_score DESC) as prev_question_score,
    LEAD(qws.question_score, 1) OVER (ORDER BY qws.question_score DESC) as next_question_score,
    CASE 
        WHEN qws.has_highest_scoring_answer = TRUE THEN 'Has Highest Scoring Answer'
        ELSE 'Does Not Have Highest Scoring Answer'
    END as answer_status,
    CASE 
        WHEN qws.answer_quality = 'Highlyrated' AND qws.engagement_score > 10 THEN 'Excellent'
        WHEN qws.answer_quality = 'Highlyrated' OR qws.engagement_score > 5 THEN 'Good'
        WHEN qws.answer_quality = 'Moderate' OR qws.engagement_score > 2 THEN 'Fair'
        ELSE 'Poor'
    END as overall_quality
FROM QuestionWithStats qws
JOIN UserActivity ua ON qws.OwnerUserId = ua.Id
JOIN QuestionWithStats qws2 ON qws.question_id = qws2.question_id
LEFT JOIN TagAnalysis ta ON qws.Tags LIKE '%' || ta.TagName || '%'
WHERE qws.score_rank <= 100
  AND qws.engagement_score > 0
  AND ua.post_count > 10
  AND (
    qws.Tags IS NOT NULL 
    OR qws.Tags != ''
    OR qws.Tags IS NULL
  )
  AND qws.Title IS NOT NULL
ORDER BY qws.engagement_score DESC, qws.question_score DESC
LIMIT 200;