-- {"query": "7201.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2269} 
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
        p.LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as total_posts,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as avg_score,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        NTILE(4) OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score) as score_quartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT r.Id) as total_revisions,
        COUNT(DISTINCT c.Id) as total_comments,
        COUNT(DISTINCT b.Id) as total_badges,
        MAX(p.CreationDate) as last_post_date,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answer_count,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as total_question_score,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as total_answer_score
    FROM Users u
    LEFT JOIN PostHistory r ON r.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostStats AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        p.ParentId,
        pt.Name as PostTypeName,
        COALESCE(p.Tags, '') as Tags,
        CASE 
            WHEN p.Tags IS NULL OR p.Tags = '' THEN 0
            ELSE LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '>', '')) + 1 
        END as tag_count,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1
            ELSE 0 
        END as has_accepted_answer,
        CASE 
            WHEN p.CreationDate > DATEADD(DAY, -30, GETDATE()) THEN 'Recent'
            WHEN p.CreationDate > DATEADD(DAY, -90, GETDATE()) THEN 'Medium'
            ELSE 'Old'
        END as age_category,
        (p.Score * 1.0 / NULLIF(p.ViewCount, 0)) as score_view_ratio,
        ABS(p.Score - COALESCE((SELECT AVG(Score) FROM Posts WHERE PostTypeId = p.PostTypeId AND OwnerUserId = p.OwnerUserId), 0)) as score_deviation
    FROM Posts p
    JOIN PostTypes pt ON pt.Id = p.PostTypeId
    WHERE p.PostTypeId IN (1, 2)
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END as tag_popularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as popularity_rank,
        AVG(t.Count) OVER () as avg_tag_count
    FROM Tags t
),
UserPerformance AS (
    SELECT 
        ua.UserId,
        ua.Reputation,
        ua.Views,
        ua.UpVotes,
        ua.DownVotes,
        ua.total_revisions,
        ua.total_comments,
        ua.total_badges,
        ua.question_count,
        ua.answer_count,
        ua.total_question_score,
        ua.total_answer_score,
        CASE 
            WHEN ua.total_revisions > 0 AND ua.total_badges > 0 THEN 'Active'
            WHEN ua.total_revisions > 0 THEN 'Revision Active'
            WHEN ua.total_badges > 0 THEN 'Badge Active'
            ELSE 'Inactive'
        END as user_status,
        CASE 
            WHEN ua.total_question_score > 1000 THEN 100
            WHEN ua.total_question_score > 500 THEN 75
            WHEN ua.total_question_score > 100 THEN 50
            WHEN ua.total_question_score > 0 THEN 25
            ELSE 0
        END as question_quality_score,
        CASE 
            WHEN ua.total_answer_score > 1000 THEN 100
            WHEN ua.total_answer_score > 500 THEN 75
            WHEN ua.total_answer_score > 100 THEN 50
            WHEN ua.total_answer_score > 0 THEN 25
            ELSE 0
        END as answer_quality_score
    FROM UserActivity ua
)
SELECT 
    ps.PostId,
    ps.Title,
    ps.Score,
    ps.ViewCount,
    ps.AnswerCount,
    ps.CommentCount,
    ps.FavoriteCount,
    ps.score_view_ratio,
    ps.score_deviation,
    ps.age_category,
    CASE 
        WHEN ps.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = ps.PostTypeId) THEN 'Above Average'
        WHEN ps.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = ps.PostTypeId) * 0.5 THEN 'Average'
        ELSE 'Below Average'
    END as score_category,
    ps.PostTypeName,
    ps.Tags,
    ps.tag_count,
    ps.has_accepted_answer,
    ps.CreationDate,
    ps.LastActivityDate,
    COALESCE(UPPER(SUBSTRING(ps.Title, 1, 1)), 'Unknown') as first_char,
    REPLACE(REPLACE(REPLACE(ps.Tags, '<', ''), '>', ''), ' ', '') as clean_tags,
    CASE 
        WHEN ps.PostTypeId = 1 THEN 
            CASE 
                WHEN ps.AnswerCount > 5 THEN 'High Engagement'
                WHEN ps.AnswerCount > 2 THEN 'Medium Engagement'
                ELSE 'Low Engagement'
            END
        WHEN ps.PostTypeId = 2 THEN 
            CASE 
                WHEN ps.Score > 10 THEN 'High Value'
                WHEN ps.Score > 5 THEN 'Medium Value'
                ELSE 'Low Value'
            END
        ELSE 'N/A'
    END as engagement_level,
    ps.OwnerUserId,
    ps.ParentId,
    CASE 
        WHEN ps.OwnerUserId IS NOT NULL THEN
            (SELECT DisplayName FROM Users WHERE Id = ps.OwnerUserId)
        ELSE 'System'
    END as OwnerDisplayName,
    CASE 
        WHEN r.total_posts > 10 THEN 'Veteran Poster'
        WHEN r.total_posts > 5 THEN 'Regular Poster'
        WHEN r.total_posts > 1 THEN 'New Poster'
        ELSE 'Inactive Poster'
    END as poster_level,
    COALESCE(ua.total_comments, 0) as user_comments,
    COALESCE(ua.total_badges, 0) as user_badges,
    COALESCE(ua.question_count, 0) as user_questions,
    COALESCE(ua.answer_count, 0) as user_answers,
    ta.TagName,
    ta.Count as tag_count,
    CASE 
        WHEN ta.Count > 500 THEN 100
        WHEN ta.Count > 100 THEN 75
        WHEN ta.Count > 50 THEN 50
        WHEN ta.Count > 10 THEN 25
        ELSE 0
    END as tag_quality_score,
    ps.ParentId IS NOT NULL as is_answer,
    ABS(ps.Score - (SELECT AVG(Score) FROM Posts WHERE PostTypeId = ps.PostTypeId)) as global_deviation,
    CASE 
        WHEN ps.ViewCount > 1000 THEN 'Viral'
        WHEN ps.ViewCount > 100 THEN 'Popular'
        WHEN ps.ViewCount > 10 THEN 'Notable'
        ELSE 'Obscure'
    END as popularity_level,
    CASE 
        WHEN ps.PostTypeId = 1 AND ps.AnswerCount > 0 THEN 
            (SELECT AVG(AnswerCount) FROM Posts WHERE PostTypeId = 1 AND OwnerUserId = ps.OwnerUserId)
        ELSE NULL
    END as avg_answers_by_owner,
    CASE 
        WHEN ps.PostTypeId = 2 AND ps.ParentId IS NOT NULL THEN
            (SELECT Score FROM Posts WHERE Id = ps.ParentId)
        ELSE NULL
    END as parent_question_score,
    CASE 
        WHEN ps.CreationDate > DATEADD(MONTH, -6, GETDATE()) THEN 1
        ELSE 0
    END as recent_post,
    ps.CreationDate > DATEADD(DAY, -1, GETDATE()) as today_post,
    (SELECT COUNT(*) FROM PostHistory WHERE PostId = ps.PostId) as revision_count
FROM PostStats ps
LEFT JOIN RankedPosts r ON r.Id = ps.PostId AND r.rn = 1
LEFT JOIN UserPerformance ua ON ua.UserId = ps.OwnerUserId
LEFT JOIN TagAnalysis ta ON ta.TagName = (
    SELECT 
        CASE 
            WHEN ps.Tags IS NOT NULL THEN TRIM(SUBSTRING(ps.Tags, 2, CHARINDEX('>', ps.Tags, 2) - 2))
            ELSE NULL
        END
    FROM Posts p2
    WHERE p2.Id = ps.PostId
)
HAVING ps.Score > 0 OR ps.ViewCount > 0
    AND ps.PostTypeId IN (1, 2)
    AND (ps.CommentCount IS NULL OR ps.CommentCount < 100)
    AND (ps.FavoriteCount IS NULL OR ps.FavoriteCount < 50)
    AND ps.age_category IN ('Recent', 'Medium')
    AND (ps.score_view_ratio IS NULL OR ps.score_view_ratio > 0)
    AND ps.has_accepted_answer = 1
ORDER BY ps.CreationDate DESC, ps.Score DESC
OFFSET 0 ROWS
FETCH NEXT 1000 ROWS ONLY;