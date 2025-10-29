-- {"query": "7784.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1804}
WITH PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS user_post_rank,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS post_type_desc,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'High Visibility'
            WHEN p.ViewCount > 100 THEN 'Medium Visibility'
            ELSE 'Low Visibility'
        END AS visibility_level
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT ps.Id) AS total_posts,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 1 THEN ps.Id END) AS questions,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 2 THEN ps.Id END) AS answers,
        SUM(ps.Score) AS total_score,
        AVG(ps.Score) AS avg_score,
        MAX(ps.CreationDate) AS last_post_date,
        RANK() OVER (ORDER BY SUM(ps.Score) DESC) AS score_rank
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS tag_count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular Tag'
            WHEN t.Count > 100 THEN 'Moderate Tag'
            ELSE 'Niche Tag'
        END AS tag_category,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) - t.Count AS count_diff_from_higher,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS posts_with_tag
    FROM Tags t
),
ComplexPostAnalysis AS (
    SELECT 
        ps.Id AS PostId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.post_type_desc,
        ps.visibility_level,
        ps.user_post_rank,
        ps.CreationDate,
        ps.LastActivityDate,
        ps.Title,
        ps.Tags,
        CASE 
            WHEN ps.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Avg'
            WHEN ps.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Below Avg'
            ELSE 'Avg'
        END AS score_category,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ps.Id),
            0
        ) AS comment_count,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ps.Id AND v.VoteTypeId = 2),
            0
        ) AS upvote_count,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ps.Id AND v.VoteTypeId = 3),
            0
        ) AS downvote_count,
        COALESCE(
            (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = ps.Id AND ph.PostHistoryTypeId IN (10, 11, 12, 13)),
            0
        ) AS activity_count,
        -- compute days_active as integer number of days between dates in a dialect-agnostic way
        CAST(
            EXTRACT(EPOCH FROM (COALESCE(ps.LastActivityDate, ps.CreationDate) - ps.CreationDate)) / 86400
            AS INTEGER
        ) AS days_active,
        CASE 
            WHEN ps.AnswerCount > 0 THEN ps.AnswerCount * 100.0 / NULLIF(ps.ViewCount, 0)
            ELSE 0 
        END AS answer_ratio,
        CASE 
            WHEN ps.CommentCount > 0 THEN ps.CommentCount * 100.0 / NULLIF(ps.Score, 0)
            ELSE 0 
        END AS comment_ratio,
        CASE 
            WHEN ps.ViewCount > 0 THEN ps.Score * 100.0 / NULLIF(ps.ViewCount, 0)
            ELSE 0
        END AS score_per_view
    FROM PostStats ps
    WHERE ps.Score IS NOT NULL 
      AND ps.ViewCount IS NOT NULL
),
FinalQuery AS (
    SELECT 
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.total_posts,
        u.questions,
        u.answers,
        u.total_score,
        u.avg_score,
        u.last_post_date,
        u.score_rank,
        pa.PostId,
        pa.Score AS post_score,
        pa.ViewCount AS post_viewcount,
        pa.AnswerCount AS post_answercount,
        pa.CommentCount AS post_commentcount,
        pa.FavoriteCount AS post_favoritecount,
        pa.post_type_desc,
        pa.visibility_level,
        pa.user_post_rank,
        pa.CreationDate AS post_creation_date,
        pa.LastActivityDate AS post_last_activity_date,
        pa.Title AS post_title,
        pa.Tags AS post_tags,
        pa.score_category,
        pa.comment_count,
        pa.upvote_count,
        pa.downvote_count,
        pa.activity_count,
        pa.days_active,
        pa.answer_ratio,
        pa.comment_ratio,
        pa.score_per_view,
        ta.TagName,
        ta.tag_count,
        ta.tag_category,
        ta.posts_with_tag,
        CASE 
            WHEN pa.days_active > 30 AND pa.Score > 10 THEN 'Active High-Value'
            WHEN pa.days_active > 30 AND pa.Score <= 10 THEN 'Active Low-Value'
            WHEN pa.days_active <= 30 AND pa.Score > 10 THEN 'Recent High-Value'
            ELSE 'Recent Low-Value'
        END AS post_engagement_type
    FROM UserActivity u
    INNER JOIN ComplexPostAnalysis pa ON u.UserId = pa.OwnerUserId
    LEFT JOIN (
        SELECT 
            t.TagName,
            p.Id AS PostId
        FROM Tags t
        JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
        WHERE p.PostTypeId = 1
    ) tag_posts ON pa.PostId = tag_posts.PostId
    LEFT JOIN TagAnalysis ta ON tag_posts.TagName = ta.TagName
    WHERE u.score_rank <= 100 
      AND pa.Score > 0 
      AND pa.user_post_rank <= 10
    ORDER BY u.score_rank, pa.Score DESC, pa.days_active DESC
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    Views,
    UpVotes,
    DownVotes,
    total_posts,
    questions,
    answers,
    total_score,
    avg_score,
    last_post_date,
    score_rank,
    PostId,
    post_score,
    post_viewcount,
    post_answercount,
    post_commentcount,
    post_favoritecount,
    post_type_desc,
    visibility_level,
    user_post_rank,
    post_creation_date,
    post_last_activity_date,
    post_title,
    post_tags,
    score_category,
    comment_count,
    upvote_count,
    downvote_count,
    activity_count,
    days_active,
    answer_ratio,
    comment_ratio,
    score_per_view,
    TagName,
    tag_count,
    tag_category,
    posts_with_tag,
    post_engagement_type,
    CASE 
        WHEN total_score > 1000 AND avg_score > 5 THEN 'Top Performer'
        WHEN total_score > 500 AND avg_score > 3 THEN 'Regular Contributor'
        WHEN total_score > 100 AND avg_score > 1 THEN 'Occasional Contributor'
        ELSE 'New Contributor'
    END AS user_status
FROM FinalQuery
WHERE (post_engagement_type = 'Active High-Value' OR post_engagement_type = 'Recent High-Value')
  AND tag_category IS NOT NULL
  AND tag_count > 10
  AND answer_ratio > 0.05
ORDER BY score_rank, post_score DESC, days_active DESC
LIMIT 1000;