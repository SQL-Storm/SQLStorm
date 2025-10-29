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
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS total_posts_by_user,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS avg_score_by_user,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Question with Answers'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 1 AND p.AnswerCount = 0 THEN 'Question without Answers'
            ELSE 'Other'
        END AS post_category
    FROM Posts p
    WHERE p.CreationDate >= TIMESTAMP '2020-01-01' 
      AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS total_posts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS total_questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS total_answers,
        AVG(p.Score) AS avg_post_score,
        MAX(p.CreationDate) AS latest_post_date,
        COUNT(DISTINCT b.Id) AS total_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id ELSE NULL END) AS gold_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id ELSE NULL END) AS silver_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id ELSE NULL END) AS bronze_badges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= TIMESTAMP '2019-01-01'
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
        COALESCE(r.prev_score, 0) AS prev_score,
        COALESCE(r.avg_score_by_user, 0) AS avg_score_by_user,
        CASE 
            WHEN r.Score > 100 THEN 'Highly Rated'
            WHEN r.Score > 50 THEN 'Moderately Rated'
            WHEN r.Score > 10 THEN 'Low Rated'
            ELSE 'Very Low Rated'
        END AS rating_category,
        CASE 
            WHEN r.ViewCount > 10000 THEN 'Viral'
            WHEN r.ViewCount > 5000 THEN 'Popular'
            WHEN r.ViewCount > 1000 THEN 'Notable'
            ELSE 'Regular'
        END AS popularity_level,
        CASE 
            WHEN r.AnswerCount > 5 THEN 'Well Answered'
            WHEN r.AnswerCount > 0 THEN 'Answered'
            ELSE 'Unanswered'
        END AS answer_status,
        COALESCE(r.Title, '') AS title_safe,
        COALESCE(r.Tags, '') AS tags_safe,
        CASE 
            WHEN r.Title LIKE '%how%' OR r.Title LIKE '%what%' OR r.Title LIKE '%why%' THEN 'Query Type'
            WHEN r.Title LIKE '%best%' OR r.Title LIKE '%fastest%' OR r.Title LIKE '%efficient%' THEN 'Best Practice'
            ELSE 'General'
        END AS question_type,
        CAST((EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - r.CreationDate) ) / 86400) AS INTEGER) AS days_since_creation
    FROM RankedPosts r
    WHERE r.rn = 1
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(t.Count, 0) AS safe_count,
        CASE 
            WHEN t.Count > 1000 THEN 'Highly Popular'
            WHEN t.Count > 500 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Low'
        END AS tag_popularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS popularity_rank
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND t.TagName <> ''
),
PostHistorySummary AS (
    SELECT 
        ph.PostId,
        COUNT(*) AS history_count,
        MAX(ph.CreationDate) AS last_history_date,
        COUNT(DISTINCT ph.PostHistoryTypeId) AS unique_types,
        STRING_AGG(ph.Comment, '; ') AS comment_summary
    FROM PostHistory ph
    WHERE ph.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY ph.PostId
)
SELECT 
    qs.Id AS PostId,
    qs.OwnerUserId,
    qs.Score,
    qs.ViewCount,
    qs.CreationDate,
    CASE 
        WHEN qs.title_safe IS NULL OR qs.title_safe = '' THEN 'No Title'
        WHEN CHAR_LENGTH(qs.title_safe) > 100 THEN SUBSTRING(qs.title_safe FROM 1 FOR 100) || '...'
        ELSE qs.title_safe
    END AS truncated_title,
    CASE 
        WHEN qs.tags_safe IS NULL OR qs.tags_safe = '' THEN 'No Tags'
        ELSE qs.tags_safe
    END AS normalized_tags,
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
    ta.Count AS tag_count,
    ta.tag_popularity,
    phs.history_count,
    phs.last_history_date,
    phs.unique_types,
    phs.comment_summary,
    CASE 
        WHEN qs.days_since_creation < 30 THEN 'Recent'
        WHEN qs.days_since_creation < 90 THEN 'Medium Age'
        ELSE 'Old'
    END AS post_age_category,
    CASE 
        WHEN qs.Score > qs.avg_score_by_user THEN 'Above Average'
        WHEN qs.Score < qs.avg_score_by_user THEN 'Below Average'
        ELSE 'Average'
    END AS score_position,
    CASE 
        WHEN qs.ViewCount > qs.avg_score_by_user * 100 THEN 'High Engagement'
        WHEN qs.ViewCount > qs.avg_score_by_user * 10 THEN 'Medium Engagement'
        ELSE 'Low Engagement'
    END AS engagement_level,
    CASE 
        WHEN qs.AnswerCount > 0 AND qs.CommentCount > 0 THEN 'Active Discussion'
        WHEN qs.AnswerCount > 0 THEN 'Answered'
        WHEN qs.CommentCount > 0 THEN 'Discussed'
        ELSE 'Quiet'
    END AS activity_level,
    'Performance Benchmark' AS test_query_type,
    CASE 
        WHEN qs.Score > 100 AND qs.ViewCount > 1000 THEN 'High Performer'
        WHEN qs.Score >= 50 AND qs.ViewCount >= 500 THEN 'Good Performer'
        WHEN qs.Score >= 10 AND qs.ViewCount >= 100 THEN 'Moderate Performer'
        ELSE 'Standard'
    END AS performance_category,
    ROW_NUMBER() OVER (ORDER BY qs.Score DESC, qs.ViewCount DESC) AS performance_rank
FROM QuestionMetrics qs
JOIN UserStats us ON qs.OwnerUserId = us.UserId
LEFT JOIN TagAnalysis ta ON qs.tags_safe LIKE '%' || ta.TagName || '%'
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
  AND (phs.history_count >= 0 OR phs.history_count IS NULL)
ORDER BY qs.Score DESC, qs.ViewCount DESC, qs.CreationDate DESC;