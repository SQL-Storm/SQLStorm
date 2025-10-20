WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        CAST(t.TagName AS VARCHAR(500)) AS tag_path,
        1 AS level
    FROM Tags t
    WHERE t.Count > 1000

    UNION ALL

    SELECT 
        t2.Id,
        t2.TagName,
        t2.Count,
        CAST(th.tag_path || ' -> ' || t2.TagName AS VARCHAR(500)) AS tag_path,
        th.level + 1 AS level
    FROM Tags t2
    INNER JOIN tag_hierarchy th ON t2.Id <> th.Id
    WHERE th.level < 3
        AND t2.Count > 500
),
user_expertise AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS questions_asked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answers_given,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 10 THEN p.Id END) AS high_score_answers,
        SUM(p.Score) AS total_score,
        AVG(p.Score) AS avg_score,
        COUNT(DISTINCT b.Id) AS badge_count,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS gold_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS silver_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS bronze_badges,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS median_score,
        STDDEV(p.Score) AS score_stddev
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
        AND u.CreationDate < (CAST('2024-10-01' AS DATE) - INTERVAL '180' DAY)
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
post_analytics AS (
    SELECT 
        p.Id,
        p.Title,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Tags,
        p.CreationDate,
        p.OwnerUserId,
        (EXTRACT(EPOCH FROM (COALESCE(p.ClosedDate, CAST('2024-10-01 12:34:56' AS TIMESTAMP)) - p.CreationDate))/3600) AS hours_to_close,
        COUNT(DISTINCT ph.Id) AS edit_count,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.Id END) AS content_edits,
        COUNT(DISTINCT v.Id) AS vote_count,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS upvote_count,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS downvote_count,
        COUNT(DISTINCT c.Id) AS comment_count_verified,
        AVG(c.Score) AS avg_comment_score,
        COUNT(DISTINCT pl.Id) AS linked_post_count,
        CASE 
            WHEN p.ViewCount > 0 THEN CAST(p.Score AS DOUBLE PRECISION) / p.ViewCount * 100
            ELSE 0 
        END AS engagement_rate,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS score_rank,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC) AS view_rank,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_post_score,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS next_post_score
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
    WHERE p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '365' DAY)
        AND p.Score > 0
    GROUP BY p.Id, p.Title, p.PostTypeId, p.Score, p.ViewCount, p.AnswerCount, 
             p.CommentCount, p.FavoriteCount, p.Tags, p.CreationDate, p.OwnerUserId, p.ClosedDate
),
temporal_patterns AS (
    SELECT 
        DATE_TRUNC('month', p.CreationDate) AS month,
        EXTRACT(DOW FROM p.CreationDate) AS day_of_week,
        EXTRACT(HOUR FROM p.CreationDate) AS hour_of_day,
        COUNT(*) AS post_count,
        AVG(p.Score) AS avg_score,
        AVG(p.ViewCount) AS avg_views,
        STDDEV(p.Score) AS score_stddev,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY p.Score) AS q1_score,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY p.Score) AS q3_score,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS closed_posts,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS accepted_answers
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
        AND p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '2' YEAR)
    GROUP BY DATE_TRUNC('month', p.CreationDate), 
             EXTRACT(DOW FROM p.CreationDate), 
             EXTRACT(HOUR FROM p.CreationDate)
)
SELECT 
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.total_posts,
    ue.questions_asked,
    ue.answers_given,
    ue.high_score_answers,
    ue.total_score,
    ue.avg_score,
    ue.median_score,
    ue.score_stddev,
    ue.gold_badges,
    ue.silver_badges,
    ue.bronze_badges,
    pa.Id AS post_id,
    pa.Title,
    pa.Score AS post_score,
    pa.ViewCount,
    pa.engagement_rate,
    pa.score_rank,
    pa.view_rank,
    pa.edit_count,
    pa.content_edits,
    pa.upvote_count,
    pa.downvote_count,
    pa.linked_post_count,
    pa.hours_to_close,
    tp.avg_score AS temporal_avg_score,
    tp.avg_views AS temporal_avg_views,
    tp.score_stddev AS temporal_score_stddev,
    tp.q1_score AS temporal_q1_score,
    tp.q3_score AS temporal_q3_score,
    th.tag_path,
    th.level AS tag_hierarchy_level,
    CASE 
        WHEN ue.Reputation > 10000 AND ue.gold_badges > 5 THEN 'Expert'
        WHEN ue.Reputation > 5000 AND ue.silver_badges > 10 THEN 'Advanced'
        WHEN ue.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS user_tier,
    CASE 
        WHEN pa.Score > 100 AND pa.ViewCount > 10000 THEN 'Viral'
        WHEN pa.Score > 50 AND pa.ViewCount > 5000 THEN 'Popular'
        WHEN pa.Score > 10 THEN 'Well-Received'
        ELSE 'Standard'
    END AS post_category,
    ROW_NUMBER() OVER (PARTITION BY ue.UserId ORDER BY pa.Score DESC) AS user_post_rank,
    NTILE(10) OVER (ORDER BY ue.Reputation DESC) AS reputation_decile,
    CUME_DIST() OVER (ORDER BY pa.Score) AS score_percentile,
    FIRST_VALUE(pa.Title) OVER (PARTITION BY ue.UserId ORDER BY pa.Score DESC) AS users_best_post
FROM user_expertise ue
INNER JOIN post_analytics pa ON ue.UserId = pa.OwnerUserId
INNER JOIN temporal_patterns tp ON DATE_TRUNC('month', pa.CreationDate) = tp.month
    AND EXTRACT(DOW FROM pa.CreationDate) = tp.day_of_week
    AND EXTRACT(HOUR FROM pa.CreationDate) = tp.hour_of_day
LEFT JOIN tag_hierarchy th ON pa.Tags LIKE '%' || th.TagName || '%'
WHERE pa.score_rank <= 1000
    AND ue.total_posts >= 10
    AND pa.ViewCount > 100
GROUP BY
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.total_posts,
    ue.questions_asked,
    ue.answers_given,
    ue.high_score_answers,
    ue.total_score,
    ue.avg_score,
    ue.median_score,
    ue.score_stddev,
    ue.gold_badges,
    ue.silver_badges,
    ue.bronze_badges,
    pa.Id,
    pa.Title,
    pa.Score,
    pa.ViewCount,
    pa.engagement_rate,
    pa.score_rank,
    pa.view_rank,
    pa.edit_count,
    pa.content_edits,
    pa.upvote_count,
    pa.downvote_count,
    pa.linked_post_count,
    pa.hours_to_close,
    tp.avg_score,
    tp.avg_views,
    tp.score_stddev,
    tp.q1_score,
    tp.q3_score,
    th.tag_path,
    th.level,
    pa.CreationDate,
    ue.Reputation
ORDER BY ue.Reputation DESC, pa.Score DESC
LIMIT 5000;