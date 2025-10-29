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
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) AS mov_avg_score,
        NTILE(4) OVER (ORDER BY p.Score) AS quartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answers,
        SUM(p.Score) AS total_score,
        AVG(p.Score) AS avg_score,
        MAX(p.CreationDate) AS last_post_date,
        MIN(p.CreationDate) AS first_post_date,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END), 0) AS total_question_views,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE 0 END), 0) AS total_answer_views,
        STRING_AGG(DISTINCT p.Tags, '; ') AS all_tags,
        COUNT(DISTINCT b.Id) AS badge_count
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
QuestionStats AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS actual_answer_count,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS comment_count,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS upvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS downvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5) AS favorite_count,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Active'
        END AS post_status,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.AnswerCount > 0 THEN 'Has Answers'
            ELSE 'Unanswered'
        END AS answer_status,
        (p.Score * 1.0 / NULLIF(p.ViewCount, 0)) AS score_to_view_ratio,
        (p.ViewCount * 1.0 / NULLIF(p.AnswerCount, 0)) AS views_per_answer,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS popularity_rank
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS related_posts,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS avg_score_by_tag,
        (SELECT MAX(p.ViewCount) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS max_views_by_tag,
        (SELECT COUNT(DISTINCT p.OwnerUserId) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS unique_posters,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END AS tag_category
    FROM Tags t
    WHERE t.Count > 0
),
ComplexJoinResult AS (
    SELECT 
        rs.Id AS PostId,
        rs.OwnerUserId,
        rs.Score,
        rs.ViewCount,
        rs.CreationDate,
        rs.Title,
        rs.Tags,
        rs.AnswerCount,
        rs.CommentCount,
        rs.FavoriteCount,
        rs.rn,
        rs.prev_score,
        rs.mov_avg_score,
        rs.quartile,
        us.Reputation,
        us.DisplayName,
        us.Views AS user_views,
        us.total_posts,
        us.questions,
        us.answers,
        us.total_score,
        us.avg_score,
        us.last_post_date,
        us.first_post_date,
        us.total_question_views,
        us.total_answer_views,
        us.all_tags,
        us.badge_count,
        qs.QuestionId,
        qs.Title AS QuestionTitle,
        qs.Score AS QuestionScore,
        qs.ViewCount AS QuestionViewCount,
        qs.AnswerCount AS QuestionAnswerCount,
        qs.CommentCount AS QuestionCommentCount,
        qs.FavoriteCount AS QuestionFavoriteCount,
        qs.CreationDate AS QuestionCreationDate,
        qs.post_status,
        qs.answer_status,
        qs.score_to_view_ratio,
        qs.views_per_answer,
        qs.popularity_rank,
        ta.TagName,
        ta.Count AS TagCount,
        ta.related_posts,
        ta.avg_score_by_tag,
        ta.max_views_by_tag,
        ta.unique_posters,
        ta.tag_category,
        us.UpVotes AS UserUpVotes,
        us.DownVotes AS UserDownVotes
    FROM RankedPosts rs
    LEFT JOIN UserStats us ON rs.OwnerUserId = us.UserId
    LEFT JOIN QuestionStats qs ON rs.Id = qs.QuestionId
    LEFT JOIN TagAnalysis ta ON rs.Tags LIKE '%' || ta.TagName || '%'
),
FinalAggregatedReport AS (
    SELECT 
        COUNT(*) AS total_records,
        COUNT(DISTINCT OwnerUserId) AS unique_users,
        COUNT(DISTINCT QuestionId) AS unique_questions,
        COUNT(DISTINCT PostId) AS unique_posts,
        COUNT(DISTINCT TagName) AS unique_tags,
        AVG(Score) AS avg_post_score,
        MAX(Score) AS max_post_score,
        MIN(Score) AS min_post_score,
        AVG(Reputation) AS avg_user_reputation,
        SUM(UserUpVotes) AS total_upvotes,
        SUM(UserDownVotes) AS total_downvotes,
        SUM(ViewCount) AS total_views,
        AVG(ViewCount) AS avg_views,
        SUM(AnswerCount) AS total_answers,
        SUM(CommentCount) AS total_comments,
        SUM(FavoriteCount) AS total_favorites,
        SUM(total_score) AS user_total_score,
        SUM(total_posts) AS user_total_posts,
        MAX(CAST(CreationDate AS VARCHAR) || '|' || CAST(PostId AS VARCHAR)) AS last_post_info,
        STRING_AGG(DISTINCT DisplayName, ', ') AS all_user_names,
        STRING_AGG(DISTINCT TagName, ', ') AS all_tags_listed,
        MAX(CASE WHEN post_status = 'Active' THEN 1 ELSE 0 END) AS has_active_posts,
        MAX(CASE WHEN answer_status = 'Answered' THEN 1 ELSE 0 END) AS has_answered_questions,
        AVG(score_to_view_ratio) AS avg_score_to_view_ratio,
        AVG(views_per_answer) AS avg_views_per_answer
    FROM ComplexJoinResult
)
SELECT 
    'Performance Benchmark Report' AS report_title,
    total_records,
    unique_users,
    unique_questions,
    unique_posts,
    unique_tags,
    ROUND(CAST(avg_post_score AS numeric), 2) AS avg_post_score,
    max_post_score,
    min_post_score,
    ROUND(CAST(avg_user_reputation AS numeric), 0) AS avg_user_reputation,
    total_upvotes,
    total_downvotes,
    total_views,
    ROUND(CAST(avg_views AS numeric), 0) AS avg_views,
    total_answers,
    total_comments,
    total_favorites,
    user_total_score,
    user_total_posts,
    last_post_info,
    CASE 
        WHEN LENGTH(COALESCE(all_user_names, '')) > 0 THEN SUBSTRING(all_user_names FROM 1 FOR 100) || '...' 
        ELSE 'No users found' 
    END AS sample_user_names,
    CASE 
        WHEN LENGTH(COALESCE(all_tags_listed, '')) > 0 THEN SUBSTRING(all_tags_listed FROM 1 FOR 200) || '...' 
        ELSE 'No tags found' 
    END AS sample_tags,
    has_active_posts,
    has_answered_questions,
    ROUND(CAST(avg_score_to_view_ratio AS numeric), 4) AS avg_score_to_view_ratio,
    ROUND(CAST(avg_views_per_answer AS numeric), 2) AS avg_views_per_answer,
    CASE 
        WHEN total_records > 10000 THEN 'High Performance'
        WHEN total_records > 5000 THEN 'Medium Performance'
        ELSE 'Low Performance'
    END AS performance_category,
    CAST('2024-10-01 12:34:56' AS timestamp) AS generated_at,
    CASE 
        WHEN (total_upvotes + total_downvotes) > 0 THEN 
            ROUND(CAST((total_upvotes * 100.0 / (total_upvotes + total_downvotes)) AS numeric), 2)
        ELSE 0 
    END AS upvote_percentage,
    CASE 
        WHEN total_views > 0 THEN 
            ROUND(CAST((total_answers * 100.0 / total_views) AS numeric), 4)
        ELSE 0 
    END AS answer_ratio_to_views,
    CASE 
        WHEN avg_post_score > 0 THEN 
            ROUND(CAST((total_comments * 100.0 / avg_post_score) AS numeric), 4)
        ELSE 0 
    END AS comment_ratio_to_score,
    (SELECT COUNT(*) FROM (
        SELECT OwnerUserId 
        FROM Posts 
        WHERE PostTypeId = 1 
        GROUP BY OwnerUserId 
        HAVING COUNT(*) > 10
    ) sub) AS prolific_question_askers,
    (SELECT COUNT(*) FROM (
        SELECT OwnerUserId 
        FROM Posts 
        WHERE PostTypeId = 2 
        GROUP BY OwnerUserId 
        HAVING COUNT(*) > 100
    ) sub) AS prolific_answerers,
    (SELECT COUNT(*) FROM (
        SELECT UserId 
        FROM Badges 
        GROUP BY UserId 
        HAVING COUNT(*) > 50
    ) sub) AS prolific_badge_earners,
    (SELECT COUNT(*) FROM (
        SELECT UserId 
        FROM Votes 
        WHERE VoteTypeId IN (1, 2, 3) 
        GROUP BY UserId 
        HAVING COUNT(*) > 1000
    ) sub) AS prolific_voters,
    CASE 
        WHEN total_records > 0 THEN 
            ROUND(CAST((total_upvotes * 1.0 / total_records) AS numeric), 4)
        ELSE 0 
    END AS upvotes_per_record,
    CASE 
        WHEN total_records > 0 THEN 
            ROUND(CAST((total_comments * 1.0 / total_records) AS numeric), 4)
        ELSE 0 
    END AS comments_per_record,
    CASE 
        WHEN total_records > 0 THEN 
            ROUND(CAST((total_favorites * 1.0 / total_records) AS numeric), 4)
        ELSE 0 
    END AS favorites_per_record,
    'Full Report Generated' AS status,
    NULLIF(1, 0) AS verification_flag
FROM FinalAggregatedReport
WHERE total_records > 0
ORDER BY total_records DESC
LIMIT 1;