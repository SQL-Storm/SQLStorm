-- {"query": "7427.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1954} 
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
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as total_posts_by_user,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as avg_score_by_user,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Question with Answers'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 1 AND p.AnswerCount = 0 THEN 'Question without Answers'
            ELSE 'Other'
        END as post_category
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01' 
      AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as total_posts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as total_questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as total_answers,
        AVG(p.Score) as avg_post_score,
        MAX(p.CreationDate) as latest_post_date,
        COUNT(DISTINCT b.Id) as total_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id ELSE NULL END) as gold_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id ELSE NULL END) as silver_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id ELSE NULL END) as bronze_badges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2019-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
QuestionMetrics AS (
    SELECT 
        r.Id,
        r.OwnerUserId,
        r.Score,
        r.ViewCount,
        r.CreationDate,
        r.Tags,
        r.AnswerCount,
        r.CommentCount,
        r.FavoriteCount,
        COALESCE(r.prev_score, 0) as prev_score,
        COALESCE(r.avg_score_by_user, 0) as avg_score_by_user,
        CASE 
            WHEN r.Score > 100 THEN 'Highly Rated'
            WHEN r.Score > 50 THEN 'Moderately Rated'
            WHEN r.Score > 10 THEN 'Low Rated'
            ELSE 'Very Low Rated'
        END as rating_category,
        CASE 
            WHEN r.ViewCount > 10000 THEN 'Viral'
            WHEN r.ViewCount > 5000 THEN 'Popular'
            WHEN r.ViewCount > 1000 THEN 'Notable'
            ELSE 'Regular'
        END as popularity_level,
        CASE 
            WHEN r.AnswerCount > 5 THEN 'Well Answered'
            WHEN r.AnswerCount > 0 THEN 'Answered'
            ELSE 'Unanswered'
        END as answer_status,
        ISNULL(r.Title, '') as title_safe,
        ISNULL(r.Tags, '') as tags_safe,
        CASE 
            WHEN r.Title LIKE '%how%' OR r.Title LIKE '%what%' OR r.Title LIKE '%why%' THEN 'Query Type'
            WHEN r.Title LIKE '%best%' OR r.Title LIKE '%fastest%' OR r.Title LIKE '%efficient%' THEN 'Best Practice'
            ELSE 'General'
        END as question_type,
        DATEDIFF(day, r.CreationDate, GETDATE()) as days_since_creation
    FROM RankedPosts r
    WHERE r.rn = 1
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        ISNULL(t.Count, 0) as safe_count,
        CASE 
            WHEN t.Count > 1000 THEN 'Highly Popular'
            WHEN t.Count > 500 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Low'
        END as tag_popularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as popularity_rank
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND t.TagName != ''
),
PostHistorySummary AS (
    SELECT 
        ph.PostId,
        COUNT(*) as history_count,
        MAX(ph.CreationDate) as last_history_date,
        COUNT(DISTINCT ph.PostHistoryTypeId) as unique_types,
        STRING_AGG(ph.Comment, '; ') as comment_summary
    FROM PostHistory ph
    WHERE ph.CreationDate >= '2020-01-01'
    GROUP BY ph.PostId
)
SELECT 
    qs.Id as PostId,
    qs.OwnerUserId,
    qs.Score,
    qs.ViewCount,
    qs.CreationDate,
    CASE 
        WHEN qs.Title IS NULL OR qs.Title = '' THEN 'No Title'
        WHEN LEN(qs.Title) > 100 THEN LEFT(qs.Title, 100) + '...'
        ELSE qs.Title
    END as truncated_title,
    CASE 
        WHEN qs.Tags IS NULL OR qs.Tags = '' THEN 'No Tags'
        ELSE qs.Tags
    END as normalized_tags,
    qs.AnswerCount,
    qs.CommentCount,
    qs.FavoriteCount,
    qs.prev_score,
    qs.avg_score_by_user,
    qs.rating_category,
    qs.popularity_level,
    qs.answer_status,
    qs.question_type,
    qs.days_since_creation,
    us.DisplayName,
    us.Reputation,
    us.total_posts,
    us.total_questions,
    us.total_answers,
    us.avg_post_score,
    us.latest_post_date,
    us.total_badges,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    ta.TagName,
    ta.Count as tag_count,
    ta.tag_popularity,
    phs.history_count,
    phs.last_history_date,
    phs.unique_types,
    phs.comment_summary,
    CASE 
        WHEN qs.days_since_creation < 30 THEN 'Recent'
        WHEN qs.days_since_creation < 90 THEN 'Medium Age'
        ELSE 'Old'
    END as post_age_category,
    CASE 
        WHEN qs.Score > qs.avg_score_by_user THEN 'Above Average'
        WHEN qs.Score < qs.avg_score_by_user THEN 'Below Average'
        ELSE 'Average'
    END as score_position,
    CASE 
        WHEN qs.ViewCount > qs.avg_score_by_user * 100 THEN 'High Engagement'
        WHEN qs.ViewCount > qs.avg_score_by_user * 10 THEN 'Medium Engagement'
        ELSE 'Low Engagement'
    END as engagement_level,
    CASE 
        WHEN qs.AnswerCount > 0 AND qs.CommentCount > 0 THEN 'Active Discussion'
        WHEN qs.AnswerCount > 0 THEN 'Answered'
        WHEN qs.CommentCount > 0 THEN 'Discussed'
        ELSE 'Quiet'
    END as activity_level,
    'Performance Benchmark' as test_query_type,
    CASE 
        WHEN qs.Score > 100 AND qs.ViewCount > 1000 THEN 'High Performer'
        WHEN qs.Score >= 50 AND qs.ViewCount >= 500 THEN 'Good Performer'
        WHEN qs.Score >= 10 AND qs.ViewCount >= 100 THEN 'Moderate Performer'
        ELSE 'Standard'
    END as performance_category,
    ROW_NUMBER() OVER (ORDER BY qs.Score DESC, qs.ViewCount DESC) as performance_rank
FROM QuestionMetrics qs
JOIN UserStats us ON qs.OwnerUserId = us.UserId
LEFT JOIN Tags ta ON qs.Tags LIKE '%' + ta.TagName + '%' 
LEFT JOIN PostHistorySummary phs ON qs.Id = phs.PostId
WHERE qs.Score > 0 
  AND qs.ViewCount > 0
  AND qs.days_since_creation >= 0
  AND qs.days_since_creation <= 365
  AND (ta.tag_popularity IN ('Highly Popular', 'Popular') OR ta.TagName IS NULL)
  AND (
    qs.AnswerCount IS NOT NULL OR qs.CommentCount IS NOT NULL OR qs.FavoriteCount IS NOT NULL
  )
  AND (
    us.total_posts > 0 AND us.total_questions > 0
  )
  AND phs.history_count >= 0
ORDER BY qs.Score DESC, qs.ViewCount DESC, qs.CreationDate DESC
OPTION (MAXDOP 4, RECOMPILE, OPTIMIZE FOR UNKNOWN)