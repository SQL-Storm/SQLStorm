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
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS cumulative_score,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS user_post_count,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Question with Answers'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS post_category
    FROM Posts p
    WHERE p.CreationDate >= TIMESTAMP '2022-01-01'
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COALESCE(SUM(p.Score), 0) AS total_score,
        COUNT(p.Id) AS posts_count,
        MAX(p.CreationDate) AS last_post_date,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS questions_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answers_count,
        COUNT(b.Id) AS badges_count,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 1 THEN b.Name END, ', ') AS gold_badges,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 2 THEN b.Name END, ', ') AS silver_badges,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 3 THEN b.Name END, ', ') AS bronze_badges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
PostAnalysis AS (
    SELECT 
        r.Id,
        r.PostTypeId,
        r.OwnerUserId,
        r.Score,
        r.ViewCount,
        r.CreationDate,
        r.Title,
        r.Tags,
        r.AnswerCount,
        r.CommentCount,
        r.FavoriteCount,
        r.rn,
        r.prev_score,
        r.cumulative_score,
        r.user_post_count,
        r.post_category,
        CASE 
            WHEN r.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= TIMESTAMP '2022-01-01') THEN 'Above Avg'
            WHEN r.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= TIMESTAMP '2022-01-01') THEN 'Below Avg'
            ELSE 'Avg'
        END AS score_ranking,
        CASE 
            WHEN r.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= TIMESTAMP '2022-01-01') THEN 'High Views'
            ELSE 'Low Views'
        END AS view_category,
        CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - r.CreationDate)) / 86400 AS INTEGER) AS days_since_creation,
        CAST(EXTRACT(EPOCH FROM (r.CreationDate - LAG(r.CreationDate) OVER (PARTITION BY r.OwnerUserId ORDER BY r.CreationDate))) / 86400 AS INTEGER) AS days_between_posts
    FROM RankedPosts r
    WHERE r.rn <= 5
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.IsRequired,
        t.IsModeratorOnly,
        t.ExcerptPostId,
        t.WikiPostId,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) AS prev_count,
        FIRST_VALUE(t.Count) OVER (ORDER BY t.Count ASC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS min_count,
        FIRST_VALUE(t.Count) OVER (ORDER BY t.Count DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS max_count,
        PERCENT_RANK() OVER (ORDER BY t.Count) AS count_percentile,
        CASE 
            WHEN t.Count >= (SELECT AVG(Count) FROM Tags) THEN 'Above Avg'
            ELSE 'Below Avg'
        END AS count_category
    FROM Tags t
    WHERE t.Count > 100
),
ComplexUserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COALESCE(ua.total_score, 0) AS net_score,
        COALESCE(ua.posts_count, 0) AS total_posts,
        COALESCE(ua.questions_count, 0) AS questions,
        COALESCE(ua.answers_count, 0) AS answers,
        COALESCE(ua.badges_count, 0) AS total_badges,
        COALESCE(ua.gold_badges, '') AS gold_badges_list,
        COALESCE(ua.silver_badges, '') AS silver_badges_list,
        COALESCE(ua.bronze_badges, '') AS bronze_badges_list,
        CASE 
            WHEN ua.total_score > (SELECT AVG(total_score) FROM UserActivity) THEN 'High Scorer'
            WHEN ua.total_score < (SELECT AVG(total_score) FROM UserActivity) THEN 'Low Scorer'
            ELSE 'Average Scorer'
        END AS scorer_category,
        CASE 
            WHEN ua.posts_count > (SELECT AVG(posts_count) FROM UserActivity) THEN 'Active Poster'
            WHEN ua.posts_count < (SELECT AVG(posts_count) FROM UserActivity) THEN 'Inactive Poster'
            ELSE 'Average Poster'
        END AS poster_category,
        CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate)) / 86400 AS INTEGER) AS user_age_days,
        CASE 
            WHEN CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate)) / 86400 AS INTEGER) > 365 THEN 'Veteran'
            WHEN CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate)) / 86400 AS INTEGER) > 180 THEN 'Regular'
            ELSE 'Newbie'
        END AS user_status
    FROM Users u
    FULL OUTER JOIN UserActivity ua ON u.Id = ua.UserId
    WHERE u.Reputation > 1000 OR u.Views > 1000
),
MainSelection AS (
    SELECT 
        pa.Id AS PostId,
        pa.PostTypeId,
        pa.OwnerUserId,
        pa.Score,
        pa.ViewCount,
        pa.CreationDate,
        pa.Title,
        pa.Tags,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.rn,
        pa.prev_score,
        pa.cumulative_score,
        pa.user_post_count,
        pa.post_category,
        pa.score_ranking,
        pa.view_category,
        pa.days_since_creation,
        pa.days_between_posts,
        COALESCE(ta.TagName, 'No Tags') AS most_popular_tag,
        COALESCE(ta.Count, 0) AS tag_count,
        COALESCE(ta.count_percentile, 0) AS tag_percentile,
        COALESCE(cus.DisplayName, 'Unknown User') AS UserName,
        COALESCE(cus.Reputation, 0) AS UserReputation,
        COALESCE(cus.total_posts, 0) AS UserTotalPosts,
        COALESCE(cus.questions, 0) AS UserQuestions,
        COALESCE(cus.answers, 0) AS UserAnswers,
        COALESCE(cus.total_badges, 0) AS UserBadges,
        COALESCE(cus.scorer_category, 'Unknown') AS UserScorerCategory,
        COALESCE(cus.poster_category, 'Unknown') AS UserPosterCategory,
        COALESCE(cus.user_age_days, 0) AS UserAgeDays,
        COALESCE(cus.user_status, 'Unknown') AS UserStatus,
        CASE 
            WHEN pa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= TIMESTAMP '2022-01-01')
             AND pa.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= TIMESTAMP '2022-01-01')
             AND pa.AnswerCount > 0 THEN 'High Performing'
            WHEN pa.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= TIMESTAMP '2022-01-01')
             AND pa.ViewCount < (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= TIMESTAMP '2022-01-01') THEN 'Low Performing'
            ELSE 'Average Performing'
        END AS performance_status,
        CASE 
            WHEN pa.days_since_creation > 30 AND pa.AnswerCount = 0 THEN 'Stale Question'
            WHEN pa.days_since_creation <= 7 AND pa.ViewCount > 100 THEN 'Fresh Hot'
            WHEN pa.days_since_creation <= 30 AND pa.AnswerCount > 0 THEN 'Recently Active'
            ELSE 'Other'
        END AS post_status
    FROM PostAnalysis pa
    LEFT JOIN TagAnalysis ta ON ta.Count = (
        SELECT MAX(t2.Count) FROM Tags t2
        WHERE t2.TagName IN (
            SELECT TRIM(tval) FROM (
                SELECT UNNEST(
                    STRING_TO_ARRAY(
                        REPLACE(REPLACE(pa.Tags, '<', ''), '>', ','),
                        ','
                    )
                ) AS tval
            ) AS derived_tags
            WHERE TRIM(tval) <> ''
        )
    )
    LEFT JOIN ComplexUserStats cus ON pa.OwnerUserId = cus.Id
    WHERE pa.Score IS NOT NULL 
      AND pa.Tags IS NOT NULL
      AND pa.Tags <> ''
      AND pa.CreationDate BETWEEN TIMESTAMP '2022-01-01' AND TIMESTAMP '2024-10-01 12:34:56'
),
FilteredSelection AS (
    SELECT PostId, PostTypeId, OwnerUserId, Score, ViewCount, CreationDate, Title, Tags, AnswerCount, CommentCount, FavoriteCount, rn, prev_score, cumulative_score, user_post_count, post_category, score_ranking, view_category, days_since_creation, days_between_posts, most_popular_tag, tag_count, tag_percentile, UserName, UserReputation, UserTotalPosts, UserQuestions, UserAnswers, UserBadges, UserScorerCategory, UserPosterCategory, UserAgeDays, UserStatus, performance_status, post_status
    FROM MainSelection
    WHERE post_category = 'Question with Answers'
)
SELECT PostId, PostTypeId, OwnerUserId, Score, ViewCount, CreationDate, Title, Tags, AnswerCount, CommentCount, FavoriteCount, rn, prev_score, cumulative_score, user_post_count, post_category, score_ranking, view_category, days_since_creation, days_between_posts, most_popular_tag, tag_count, tag_percentile, UserName, UserReputation, UserTotalPosts, UserQuestions, UserAnswers, UserBadges, UserScorerCategory, UserPosterCategory, UserAgeDays, UserStatus, performance_status, post_status
FROM MainSelection
WHERE PostId NOT IN (SELECT PostId FROM FilteredSelection)
ORDER BY Score DESC, ViewCount DESC, CreationDate DESC
LIMIT 10000;