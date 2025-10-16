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
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_score,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS next_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_avg_score,
        NTILE(4) OVER (ORDER BY p.Score DESC) AS score_quartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT p.Id) AS total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_count,
        COUNT(DISTINCT c.Id) AS comment_count,
        COUNT(DISTINCT b.Id) AS badge_count,
        MAX(p.CreationDate) AS last_post_date,
        MIN(p.CreationDate) AS first_post_date,
        CAST(EXTRACT(EPOCH FROM (MAX(p.CreationDate) - MIN(p.CreationDate))) / 86400 AS INTEGER) AS days_active,
        COALESCE(SUM(p.Score), 0) AS total_score,
        COALESCE(AVG(p.Score), 0) AS avg_score,
        COALESCE(MAX(p.Score), 0) AS max_score,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                CAST(COUNT(DISTINCT CASE WHEN p.Score > 0 THEN p.Id END) AS DECIMAL) * 100 / CAST(COUNT(DISTINCT p.Id) AS DECIMAL)
            ELSE 0 
        END AS positive_score_ratio,
        STRING_AGG(p.Tags, '|') AS all_tags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > (SELECT AVG(t2.Count) FROM Tags t2) THEN 'High'
            WHEN t.Count > (SELECT AVG(t2.Count) * 0.5 FROM Tags t2) THEN 'Medium'
            ELSE 'Low'
        END AS popularity_level,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS popularity_rank,
        PERCENT_RANK() OVER (ORDER BY t.Count) AS percentile_rank
    FROM Tags t
    WHERE t.Count > 0
),
ComplexPostAnalysis AS (
    SELECT 
        rp.Id AS PostId,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.LastActivityDate,
        rp.CreationDate,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.prev_score,
        rp.next_score,
        rp.rolling_avg_score,
        rp.score_quartile,
        CASE 
            WHEN rp.Score > (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.PostTypeId = 1) THEN 'Above_Avg'
            WHEN rp.Score > (SELECT AVG(p2.Score) * 0.75 FROM Posts p2 WHERE p2.PostTypeId = 1) THEN 'Near_Avg'
            ELSE 'Below_Avg'
        END AS score_category,
        CASE 
            WHEN rp.AnswerCount > 0 AND rp.Score > 0 THEN CAST(rp.Score AS DECIMAL) / rp.AnswerCount
            ELSE 0 
        END AS score_per_answer,
        CASE 
            WHEN rp.CommentCount > 0 AND rp.Score > 0 THEN CAST(rp.Score AS DECIMAL) / rp.CommentCount
            ELSE 0 
        END AS score_per_comment,
        CASE 
            WHEN rp.ViewCount > 0 THEN CAST(rp.Score AS DECIMAL) / rp.ViewCount
            ELSE 0 
        END AS score_per_view,
        CAST(EXTRACT(EPOCH FROM (rp.LastActivityDate - rp.CreationDate)) / 86400 AS INTEGER) AS days_since_last_activity,
        CASE 
            WHEN rp.next_score IS NOT NULL AND rp.next_score > rp.Score THEN 'Increasing'
            WHEN rp.prev_score IS NOT NULL AND rp.prev_score > rp.Score THEN 'Decreasing'
            ELSE 'Stable'
        END AS trend_status,
        CASE 
            WHEN EXISTS (
                SELECT 1 
                FROM PostHistory ph 
                WHERE ph.PostId = rp.Id 
                AND ph.PostHistoryTypeId IN (10, 11, 12, 13)
            ) THEN 'HasHistory'
            ELSE 'NoHistory'
        END AS post_history_status,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.PostId = rp.Id 
         AND v.VoteTypeId = 2) AS upvotes,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.PostId = rp.Id 
         AND v.VoteTypeId = 3) AS downvotes,
        (SELECT COUNT(*) 
         FROM Comments c 
         WHERE c.PostId = rp.Id) AS comment_count,
        COALESCE((SELECT COUNT(*) 
                  FROM PostLinks pl 
                  WHERE pl.PostId = rp.Id), 0) AS link_count,
        COALESCE((SELECT COUNT(*) 
                  FROM PostHistory ph 
                  WHERE ph.PostId = rp.Id 
                  AND ph.PostHistoryTypeId IN (1,2,3,4,5,6,7,8,9)), 0) AS edit_count,
        CASE 
            WHEN rp.Tags LIKE '%<%<%' THEN 'MultipleTags'
            ELSE 'SingleTag'
        END AS tag_complexity,
        CASE 
            WHEN rp.Tags LIKE '%<javascript>%' OR rp.Tags LIKE '%<python>%' THEN 'PopularTopic'
            WHEN rp.Tags LIKE '%<android>%' OR rp.Tags LIKE '%<ios>%' THEN 'MobileDev'
            ELSE 'OtherTopic'
        END AS topic_category
    FROM RankedPosts rp
    WHERE rp.rn <= 3
)
SELECT 
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.total_posts,
    uas.question_count,
    uas.answer_count,
    uas.comment_count,
    uas.badge_count,
    uas.days_active,
    uas.total_score,
    uas.avg_score,
    uas.max_score,
    uas.positive_score_ratio,
    uas.all_tags,
    ta.TagName,
    ta.Count,
    ta.popularity_level,
    ta.popularity_rank,
    ta.percentile_rank,
    cpa.PostId,
    cpa.PostTypeId,
    cpa.Score,
    cpa.ViewCount,
    cpa.LastActivityDate,
    cpa.Title,
    cpa.Tags,
    cpa.AnswerCount,
    cpa.CommentCount,
    cpa.FavoriteCount,
    cpa.prev_score,
    cpa.next_score,
    cpa.rolling_avg_score,
    cpa.score_quartile,
    cpa.score_category,
    cpa.score_per_answer,
    cpa.score_per_comment,
    cpa.score_per_view,
    cpa.days_since_last_activity,
    cpa.trend_status,
    cpa.post_history_status,
    cpa.upvotes,
    cpa.downvotes,
    cpa.comment_count AS post_comment_count,
    cpa.link_count,
    cpa.edit_count,
    cpa.tag_complexity,
    cpa.topic_category,
    CASE 
        WHEN cpa.Score > 0 AND cpa.ViewCount > 0 THEN 
            CASE 
                WHEN (CAST(cpa.Score AS DECIMAL) / cpa.ViewCount) > 0.01 THEN 'HighEngagement'
                WHEN (CAST(cpa.Score AS DECIMAL) / cpa.ViewCount) > 0.005 THEN 'MediumEngagement'
                ELSE 'LowEngagement'
            END
        ELSE 'NoData'
    END AS engagement_level,
    COALESCE(uas.total_posts, 0) + COALESCE(ta.Count, 0) + COALESCE(cpa.upvotes, 0) AS composite_metric,
    CASE 
        WHEN (uas.positive_score_ratio > 50 OR cpa.score_per_answer > 2.0 OR cpa.score_per_view > 0.005) 
            AND uas.days_active > 30 THEN 'ActiveEngager'
        ELSE 'Passive'
    END AS user_engagement_status,
    CASE 
        WHEN cpa.score_category = 'Above_Avg' AND cpa.trend_status = 'Increasing' THEN 'TrendingUp'
        WHEN cpa.score_category = 'Below_Avg' AND cpa.trend_status = 'Decreasing' THEN 'TrendingDown'
        ELSE 'Stable'
    END AS post_performance_trend,
    ROW_NUMBER() OVER (ORDER BY uas.total_score DESC, cpa.Score DESC) AS ranking,
    DENSE_RANK() OVER (ORDER BY uas.Reputation DESC) AS reputation_rank
FROM UserActivityStats uas
FULL JOIN TagAnalysis ta ON 1=1
FULL JOIN ComplexPostAnalysis cpa ON 1=1
WHERE (uas.UserId IS NOT NULL OR ta.TagName IS NOT NULL OR cpa.PostId IS NOT NULL)
  AND ( (uas.days_active > 30) OR (ta.Count > 10) OR (cpa.Score > 0) )
  AND (
    (ta.TagName IS NOT NULL AND ta.Count > 5) 
    OR 
    (cpa.PostId IS NOT NULL AND cpa.Score > 10)
    OR 
    (uas.UserId IS NOT NULL AND uas.total_posts > 5)
  )
  AND uas.Reputation IS NOT NULL
  AND (cpa.PostId IS NOT NULL OR cpa.Score IS NOT NULL OR uas.UserId IS NOT NULL)
ORDER BY 
    uas.total_score DESC,
    ta.Count DESC,
    cpa.Score DESC,
    uas.days_active DESC
OFFSET 0
FETCH NEXT 1000 ROWS ONLY;