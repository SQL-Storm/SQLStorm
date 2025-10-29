-- {"query": "7742.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2611}
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
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS row_num,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS avg_score,
        NTILE(4) OVER (ORDER BY p.Score) AS score_quartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT p.Id) AS post_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_count,
        SUM(p.Score) AS total_score,
        AVG(p.Score) AS avg_score,
        MAX(p.CreationDate) AS last_post_date,
        STRING_AGG(DISTINCT p.Tags, ', ') AS all_tags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS tag_count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > (SELECT AVG(CAST(tags_inner.Count AS NUMERIC)) FROM Tags tags_inner) THEN 'High'
            WHEN t.Count < (SELECT AVG(CAST(tags_inner.Count AS NUMERIC)) FROM Tags tags_inner) THEN 'Low'
            ELSE 'Average'
        END AS tag_popularity,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS related_posts,
        (SELECT AVG(CAST(p.Score AS NUMERIC)) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS avg_related_score
    FROM Tags t
),
ComplexPostAnalysis AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.ParentId,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.LastActivityDate,
        rp.row_num,
        rp.prev_score,
        rp.avg_score,
        rp.score_quartile,
        CASE 
            WHEN rp.Score > (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.PostTypeId = 1) THEN 'Above Average'
            WHEN rp.Score < (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.PostTypeId = 1) THEN 'Below Average'
            ELSE 'Average'
        END AS score_category,
        CASE 
            WHEN rp.Score > 10 AND rp.AnswerCount > 5 THEN 'High Engagement'
            WHEN rp.Score < 0 THEN 'Low Engagement'
            ELSE 'Moderate Engagement'
        END AS engagement_level,
        CASE 
            WHEN rp.CreationDate IS NOT NULL AND rp.LastActivityDate IS NOT NULL 
            THEN CAST(EXTRACT(EPOCH FROM (rp.LastActivityDate - rp.CreationDate)) / 86400 AS INTEGER)
            ELSE NULL
        END AS days_since_activity,
        COALESCE(rp.AnswerCount, 0) + COALESCE(rp.CommentCount, 0) + COALESCE(rp.FavoriteCount, 0) AS engagement_metric,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM Posts p2 
                WHERE p2.ParentId = rp.Id AND p2.PostTypeId = 2 AND p2.Score > 0
            ) THEN 'Has Positive Answers'
            ELSE 'No Positive Answers'
        END AS answer_status,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.Id) AS comment_count,
        COALESCE(
            (SELECT AVG(CAST(v.BountyAmount AS NUMERIC)) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 8), 
            0
        ) AS avg_bounty_amount,
        CASE 
            WHEN rp.Tags IS NOT NULL AND rp.Tags <> '' THEN 
                (SELECT COUNT(*) FROM (
                    SELECT TRIM(tag) AS tag FROM (
                        SELECT regexp_split_to_table(regexp_replace(rp.Tags, '(^<|>$)', ''), '><') AS tag
                    ) s WHERE TRIM(tag) <> ''
                ) t)
            ELSE 0
        END AS tag_count
    FROM RankedPosts rp
),
ComprehensiveAnalysis AS (
    SELECT 
        cpa.Id,
        cpa.PostTypeId,
        cpa.ParentId,
        cpa.OwnerUserId,
        cpa.Score,
        cpa.ViewCount,
        cpa.CreationDate,
        cpa.Title,
        cpa.Tags,
        cpa.AnswerCount,
        cpa.CommentCount,
        cpa.FavoriteCount,
        cpa.LastActivityDate,
        cpa.row_num,
        cpa.prev_score,
        cpa.avg_score,
        cpa.score_quartile,
        cpa.score_category,
        cpa.engagement_level,
        cpa.days_since_activity,
        cpa.engagement_metric,
        cpa.answer_status,
        cpa.comment_count,
        cpa.avg_bounty_amount,
        cpa.tag_count,
        us.DisplayName,
        us.Reputation,
        us.post_count,
        us.question_count,
        us.answer_count,
        us.total_score,
        us.avg_score AS user_avg_score,
        us.last_post_date,
        us.all_tags,
        ta.tag_count AS tag_usage_count,
        ta.tag_popularity,
        ta.related_posts,
        ta.avg_related_score,
        CASE 
            WHEN cpa.Score > 0 AND cpa.tag_count > 0 THEN 'Active with Tags'
            WHEN cpa.Score < 0 AND cpa.tag_count = 0 THEN 'Inactive without Tags'
            ELSE 'Mixed'
        END AS activity_tag_status
    FROM ComplexPostAnalysis cpa
    LEFT JOIN UserStats us ON cpa.OwnerUserId = us.UserId
    LEFT JOIN TagAnalysis ta ON EXISTS (
            SELECT 1 FROM (
                SELECT TRIM(tag) AS tag FROM (
                    SELECT regexp_split_to_table(regexp_replace(cpa.Tags, '(^<|>$)', ''), '><') AS tag
                ) s
            ) t WHERE t.tag = ta.TagName
        ) AND cpa.Tags IS NOT NULL
    WHERE cpa.Score IS NOT NULL
)
SELECT 
    ca.Id,
    ca.PostTypeId,
    ca.ParentId,
    ca.OwnerUserId,
    ca.Score,
    ca.ViewCount,
    ca.CreationDate,
    ca.Title,
    ca.Tags,
    ca.AnswerCount,
    ca.CommentCount,
    ca.FavoriteCount,
    ca.LastActivityDate,
    ca.row_num,
    ca.prev_score,
    ca.avg_score,
    ca.score_quartile,
    ca.score_category,
    ca.engagement_level,
    ca.days_since_activity,
    ca.engagement_metric,
    ca.answer_status,
    ca.comment_count,
    ca.avg_bounty_amount,
    ca.tag_count,
    ca.DisplayName,
    ca.Reputation,
    ca.post_count,
    ca.question_count,
    ca.answer_count,
    ca.total_score,
    ca.user_avg_score,
    ca.last_post_date,
    ca.all_tags,
    ca.tag_usage_count,
    ca.tag_popularity,
    ca.related_posts,
    ca.avg_related_score,
    ca.activity_tag_status,
    CASE 
        WHEN ca.Reputation > 10000 AND ca.post_count > 100 THEN 'Veteran Contributor'
        WHEN ca.Reputation > 1000 AND ca.post_count > 10 THEN 'Experienced Contributor'
        WHEN ca.Reputation < 100 AND ca.post_count < 5 THEN 'New Contributor'
        ELSE 'Regular Contributor'
    END AS contributor_level,
    DENSE_RANK() OVER (ORDER BY ca.Score DESC) AS rank_by_score,
    PERCENT_RANK() OVER (ORDER BY ca.Score) AS percentile_by_score,
    RANK() OVER (PARTITION BY ca.OwnerUserId ORDER BY ca.CreationDate) AS user_post_rank,
    ROW_NUMBER() OVER (ORDER BY ca.CreationDate) AS chronological_row,
    CASE 
        WHEN ca.score_category = 'Above Average' AND ca.engagement_level = 'High Engagement' THEN 'Top Performer'
        WHEN ca.score_category = 'Below Average' AND ca.engagement_level = 'Low Engagement' THEN 'Underperformer'
        ELSE 'Normal'
    END AS performance_status,
    COALESCE(ca.Score, 0) + COALESCE(ca.ViewCount, 0) + COALESCE(ca.CommentCount, 0) AS total_activity,
    CASE 
        WHEN ca.days_since_activity IS NOT NULL AND ca.days_since_activity <= 30 THEN 'Recently Active'
        WHEN ca.days_since_activity IS NOT NULL AND ca.days_since_activity <= 90 THEN 'Moderately Active'
        WHEN ca.days_since_activity IS NOT NULL AND ca.days_since_activity <= 365 THEN 'Occasionally Active'
        ELSE 'Inactive'
    END AS activity_frequency,
    CASE 
        WHEN ca.tag_count > 0 AND ca.related_posts > 0 THEN 
            CAST(ca.avg_related_score AS DECIMAL(10,2)) / CAST(ca.tag_count AS DECIMAL(10,2))
        ELSE 0
    END AS tag_effectiveness_score,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ca.Id AND v.VoteTypeId IN (2, 3)) AS total_votes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ca.Id) AS total_comments,
    (SELECT COUNT(*) FROM Posts p WHERE p.ParentId = ca.Id) AS child_posts_count,
    CASE 
        WHEN ca.Score > 0 AND ca.AnswerCount > 0 THEN 
            CAST(ca.Score AS DECIMAL(10,2)) / CAST(ca.AnswerCount AS DECIMAL(10,2))
        ELSE 0
    END AS score_per_answer,
    CASE 
        WHEN ca.LastActivityDate IS NOT NULL AND ca.CreationDate IS NOT NULL THEN 
            CAST(EXTRACT(EPOCH FROM (ca.LastActivityDate - ca.CreationDate)) / 86400 AS INTEGER)
        ELSE 0
    END AS days_active,
    CASE 
        WHEN ca.ViewCount > 1000 THEN 'High Visibility'
        WHEN ca.ViewCount > 100 THEN 'Medium Visibility'
        WHEN ca.ViewCount > 0 THEN 'Low Visibility'
        ELSE 'No Views'
    END AS visibility_level,
    CASE 
        WHEN ca.Score > 1000 THEN 'Elite'
        WHEN ca.Score > 100 THEN 'Prominent'
        WHEN ca.Score > 0 THEN 'Noticeable'
        WHEN ca.Score < 0 THEN 'Controversial'
        ELSE 'Neutral'
    END AS score_status,
    CASE 
        WHEN ca.AnswerCount > 10 THEN 'Highly Answered'
        WHEN ca.AnswerCount > 5 THEN 'Somewhat Answered'
        WHEN ca.AnswerCount > 0 THEN 'Slightly Answered'
        ELSE 'Unanswered'
    END AS answer_status_desc,
    CASE 
        WHEN ca.CommentCount > 20 THEN 'Heavily Commented'
        WHEN ca.CommentCount > 5 THEN 'Moderately Commented'
        WHEN ca.CommentCount > 0 THEN 'Slightly Commented'
        ELSE 'Uncommented'
    END AS comment_status_desc,
    CASE 
        WHEN ca.FavoriteCount > 100 THEN 'Highly Favorited'
        WHEN ca.FavoriteCount > 10 THEN 'Moderately Favorited'
        WHEN ca.FavoriteCount > 0 THEN 'Slightly Favorited'
        ELSE 'Not Favorited'
    END AS favorite_status_desc
FROM ComprehensiveAnalysis ca
WHERE ca.Score IS NOT NULL
    AND ca.OwnerUserId IS NOT NULL
    AND (ca.score_category = 'Above Average' OR ca.engagement_level = 'High Engagement')
    AND ca.CreationDate >= DATE '2020-01-01'
    AND (ca.Reputation > 0 OR ca.Reputation IS NULL)
    AND (ca.post_count > 0 OR ca.post_count IS NULL)
    AND (
        (ca.tag_popularity = 'High' AND ca.avg_related_score > 0)
        OR 
        (ca.answer_status = 'Has Positive Answers' AND ca.question_count > 0)
        OR 
        (ca.engagement_metric > 0 AND ca.Score > 0)
    )
ORDER BY 
    ca.Score DESC,
    ca.engagement_metric DESC,
    ca.LastActivityDate DESC
LIMIT 1000;