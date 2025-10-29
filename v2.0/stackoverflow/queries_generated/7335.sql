-- {"query": "7335.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2536} 
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
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) as mov_avg_score,
        NTILE(4) OVER (ORDER BY p.Score) as quartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answers,
        SUM(p.Score) as total_score,
        AVG(p.Score) as avg_score,
        MAX(p.CreationDate) as last_post_date,
        MIN(p.CreationDate) as first_post_date,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END), 0) as total_question_views,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE 0 END), 0) as total_answer_views,
        STRING_AGG(DISTINCT p.Tags, '; ') as all_tags,
        COUNT(DISTINCT b.Id) as badge_count
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
QuestionStats AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) as actual_answer_count,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as comment_count,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as upvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as downvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5) as favorite_count,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Active'
        END as post_status,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.AnswerCount > 0 THEN 'Has Answers'
            ELSE 'Unanswered'
        END as answer_status,
        (p.Score * 1.0 / NULLIF(p.ViewCount, 0)) as score_to_view_ratio,
        (p.ViewCount * 1.0 / NULLIF(p.AnswerCount, 0)) as views_per_answer,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) as popularity_rank
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as related_posts,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as avg_score_by_tag,
        (SELECT MAX(p.ViewCount) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as max_views_by_tag,
        (SELECT COUNT(DISTINCT p.OwnerUserId) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as unique_posters,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END as tag_category
    FROM Tags t
    WHERE t.Count > 0
),
ComplexJoinResult AS (
    SELECT 
        rs.Id as PostId,
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
        us.Views as user_views,
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
        qs.Title as QuestionTitle,
        qs.Score as QuestionScore,
        qs.ViewCount as QuestionViewCount,
        qs.AnswerCount as QuestionAnswerCount,
        qs.CommentCount as QuestionCommentCount,
        qs.FavoriteCount as QuestionFavoriteCount,
        qs.CreationDate as QuestionCreationDate,
        qs.post_status,
        qs.answer_status,
        qs.score_to_view_ratio,
        qs.views_per_answer,
        qs.popularity_rank,
        ta.TagName,
        ta.Count as TagCount,
        ta.related_posts,
        ta.avg_score_by_tag,
        ta.max_views_by_tag,
        ta.unique_posters,
        ta.tag_category
    FROM RankedPosts rs
    LEFT JOIN UserStats us ON rs.OwnerUserId = us.UserId
    LEFT JOIN QuestionStats qs ON rs.Id = qs.QuestionId
    LEFT JOIN TagAnalysis ta ON rs.Tags LIKE '%' || ta.TagName || '%'
),
FinalAggregatedReport AS (
    SELECT 
        COUNT(*) as total_records,
        COUNT(DISTINCT OwnerUserId) as unique_users,
        COUNT(DISTINCT QuestionId) as unique_questions,
        COUNT(DISTINCT PostId) as unique_posts,
        COUNT(DISTINCT TagName) as unique_tags,
        AVG(Score) as avg_post_score,
        MAX(Score) as max_post_score,
        MIN(Score) as min_post_score,
        AVG(Reputation) as avg_user_reputation,
        SUM(UpVotes) as total_upvotes,
        SUM(DownVotes) as total_downvotes,
        SUM(ViewCount) as total_views,
        AVG(ViewCount) as avg_views,
        SUM(AnswerCount) as total_answers,
        SUM(CommentCount) as total_comments,
        SUM(FavoriteCount) as total_favorites,
        SUM(total_score) as user_total_score,
        SUM(total_posts) as user_total_posts,
        MAX(CONCAT(CreationDate, '|', PostId)) as last_post_info,
        STRING_AGG(DISTINCT DisplayName, ', ') as all_user_names,
        STRING_AGG(DISTINCT TagName, ', ') as all_tags_listed,
        MAX(CASE WHEN post_status = 'Active' THEN 1 ELSE 0 END) as has_active_posts,
        MAX(CASE WHEN answer_status = 'Answered' THEN 1 ELSE 0 END) as has_answered_questions,
        AVG(score_to_view_ratio) as avg_score_to_view_ratio,
        AVG(views_per_answer) as avg_views_per_answer
    FROM ComplexJoinResult
)
SELECT 
    'Performance Benchmark Report' as report_title,
    total_records,
    unique_users,
    unique_questions,
    unique_posts,
    unique_tags,
    ROUND(avg_post_score, 2) as avg_post_score,
    max_post_score,
    min_post_score,
    ROUND(avg_user_reputation, 0) as avg_user_reputation,
    total_upvotes,
    total_downvotes,
    total_views,
    ROUND(avg_views, 0) as avg_views,
    total_answers,
    total_comments,
    total_favorites,
    user_total_score,
    user_total_posts,
    last_post_info,
    CASE 
        WHEN COUNT(all_user_names) > 0 THEN SUBSTRING(all_user_names, 1, 100) || '...' 
        ELSE 'No users found' 
    END as sample_user_names,
    CASE 
        WHEN COUNT(all_tags_listed) > 0 THEN SUBSTRING(all_tags_listed, 1, 200) || '...' 
        ELSE 'No tags found' 
    END as sample_tags,
    has_active_posts,
    has_answered_questions,
    ROUND(avg_score_to_view_ratio, 4) as avg_score_to_view_ratio,
    ROUND(avg_views_per_answer, 2) as avg_views_per_answer,
    CASE 
        WHEN total_records > 10000 THEN 'High Performance'
        WHEN total_records > 5000 THEN 'Medium Performance'
        ELSE 'Low Performance'
    END as performance_category,
    CURRENT_TIMESTAMP as generated_at,
    CASE 
        WHEN (total_upvotes + total_downvotes) > 0 THEN 
            ROUND((total_upvotes * 100.0 / (total_upvotes + total_downvotes)), 2)
        ELSE 0 
    END as upvote_percentage,
    CASE 
        WHEN total_views > 0 THEN 
            ROUND((total_answers * 100.0 / total_views), 4)
        ELSE 0 
    END as answer_ratio_to_views,
    CASE 
        WHEN avg_post_score > 0 THEN 
            ROUND((total_comments * 100.0 / avg_post_score), 4)
        ELSE 0 
    END as comment_ratio_to_score,
    (SELECT COUNT(*) FROM (
        SELECT OwnerUserId 
        FROM Posts 
        WHERE PostTypeId = 1 
        GROUP BY OwnerUserId 
        HAVING COUNT(*) > 10
    ) sub) as prolific_question_askers,
    (SELECT COUNT(*) FROM (
        SELECT OwnerUserId 
        FROM Posts 
        WHERE PostTypeId = 2 
        GROUP BY OwnerUserId 
        HAVING COUNT(*) > 100
    ) sub) as prolific_answerers,
    (SELECT COUNT(*) FROM (
        SELECT UserId 
        FROM Badges 
        GROUP BY UserId 
        HAVING COUNT(*) > 50
    ) sub) as prolific_badge_earners,
    (SELECT COUNT(*) FROM (
        SELECT UserId 
        FROM Votes 
        WHERE VoteTypeId IN (1, 2, 3) 
        GROUP BY UserId 
        HAVING COUNT(*) > 1000
    ) sub) as prolific_voters,
    CASE 
        WHEN total_records > 0 THEN 
            ROUND((total_upvotes * 1.0 / total_records), 4)
        ELSE 0 
    END as upvotes_per_record,
    CASE 
        WHEN total_records > 0 THEN 
            ROUND((total_comments * 1.0 / total_records), 4)
        ELSE 0 
    END as comments_per_record,
    CASE 
        WHEN total_records > 0 THEN 
            ROUND((total_favorites * 1.0 / total_records), 4)
        ELSE 0 
    END as favorites_per_record,
    'Full Report Generated' as status,
    NULLIF(1, 0) as verification_flag
FROM FinalAggregatedReport
HAVING total_records > 0
ORDER BY total_records DESC
LIMIT 1;