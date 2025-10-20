WITH RECURSIVE user_reputation_tiers AS (
    SELECT 
        Id,
        DisplayName,
        Reputation,
        CreationDate,
        CASE 
            WHEN Reputation >= 100000 THEN 'Elite'
            WHEN Reputation >= 25000 THEN 'Expert'
            WHEN Reputation >= 5000 THEN 'Advanced'
            WHEN Reputation >= 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS tier,
        NTILE(10) OVER (ORDER BY Reputation DESC) AS reputation_decile
    FROM Users
    WHERE Reputation > 100
),
post_engagement_metrics AS (
    SELECT 
        p.Id AS post_id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COALESCE(v.upvotes, 0) AS upvotes,
        COALESCE(v.downvotes, 0) AS downvotes,
        COALESCE(c.comment_count, 0) AS actual_comments,
        (EXTRACT(EPOCH FROM p.LastActivityDate) - EXTRACT(EPOCH FROM p.CreationDate))/86400.0 AS days_active,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS user_post_rank
    FROM Posts p
    LEFT JOIN (
        SELECT PostId, 
               SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
               SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes
        FROM Votes
        WHERE VoteTypeId IN (2, 3)
        GROUP BY PostId
    ) v ON p.Id = v.PostId
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS comment_count
        FROM Comments
        GROUP BY PostId
    ) c ON p.Id = c.PostId
    WHERE p.PostTypeId IN (1, 2)
      AND p.CreationDate >= TIMESTAMP '2020-01-01'
),
tag_performance AS (
    SELECT 
        t.TagName,
        t.Count AS tag_total_count,
        AVG(p.Score) AS avg_score,
        AVG(p.ViewCount) AS avg_views,
        COUNT(DISTINCT p.OwnerUserId) AS unique_contributors,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS median_score,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY p.Score) AS p90_score,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0) AS answer_rate
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE p.PostTypeId = 1
      AND t.Count > 100
    GROUP BY t.TagName, t.Count
),
user_interaction_graph AS (
    SELECT 
        u.Id AS user_id,
        u.tier,
        COUNT(DISTINCT p.Id) AS total_posts,
        COUNT(DISTINCT b.Id) AS total_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS gold_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS silver_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS bronze_badges,
        AVG(pem.Score) AS avg_post_score,
        MAX(pem.Score) AS max_post_score,
        SUM(pem.upvotes) AS total_upvotes,
        SUM(pem.downvotes) AS total_downvotes,
        COUNT(DISTINCT c.Id) AS comments_made,
        AVG(pem.days_active) AS avg_post_lifetime_days,
        STRING_AGG(tp.TagName, ', ' ORDER BY tp.TagName) AS top_tags
    FROM user_reputation_tiers u
    LEFT JOIN post_engagement_metrics pem ON u.Id = pem.OwnerUserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN LATERAL (
        SELECT t.TagName, 
               ROW_NUMBER() OVER (ORDER BY ta.cnt DESC) AS tp_rank
        FROM (
            SELECT tag_array.tag AS tag, COUNT(*) AS cnt
            FROM Posts p2,
                 LATERAL (
                   SELECT UNNEST(string_to_array(substring(p2.Tags, 2, length(p2.Tags)-2), '><')) AS tag
                 ) AS tag_array
            WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1
            GROUP BY tag_array.tag
        ) ta
        INNER JOIN Tags t ON t.TagName = ta.tag
        GROUP BY t.TagName, ta.cnt
        ORDER BY ta.cnt DESC
    ) tp ON tp.tp_rank <= 5
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.tier
),
answer_quality_analysis AS (
    SELECT 
        q.Id AS question_id,
        q.OwnerUserId AS question_owner,
        q.Title,
        q.Score AS question_score,
        a.Id AS answer_id,
        a.OwnerUserId AS answer_owner,
        a.Score AS answer_score,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS is_accepted,
        (EXTRACT(EPOCH FROM a.CreationDate) - EXTRACT(EPOCH FROM q.CreationDate))/3600.0 AS hours_to_answer,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS answer_rank_by_score
    FROM Posts q
    INNER JOIN Posts a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1 
      AND a.PostTypeId = 2
      AND q.CreationDate >= TIMESTAMP '2022-01-01'
      AND q.AnswerCount > 0
)
SELECT 
    uig.tier AS user_tier,
    uig.user_id,
    urt.DisplayName,
    urt.Reputation,
    uig.total_posts,
    uig.avg_post_score,
    uig.max_post_score,
    uig.total_upvotes,
    uig.total_downvotes,
    ROUND(uig.total_upvotes * 100.0 / NULLIF(uig.total_upvotes + uig.total_downvotes, 0), 2) AS upvote_percentage,
    uig.gold_badges,
    uig.silver_badges,
    uig.bronze_badges,
    uig.comments_made,
    uig.top_tags,
    COALESCE(aqa_stats.avg_answer_score, 0) AS avg_answer_score,
    COALESCE(aqa_stats.acceptance_rate, 0) AS acceptance_rate,
    COALESCE(aqa_stats.median_hours_to_answer, 0) AS median_hours_to_answer,
    COALESCE(ph_stats.edit_count, 0) AS total_edits,
    RANK() OVER (PARTITION BY uig.tier ORDER BY uig.avg_post_score DESC, uig.total_upvotes DESC) AS tier_rank
FROM user_interaction_graph uig
INNER JOIN user_reputation_tiers urt ON uig.user_id = urt.Id
LEFT JOIN (
    SELECT 
        answer_owner,
        AVG(answer_score) AS avg_answer_score,
        SUM(is_accepted) * 100.0 / NULLIF(COUNT(*), 0) AS acceptance_rate,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY hours_to_answer) AS median_hours_to_answer
    FROM answer_quality_analysis
    GROUP BY answer_owner
) aqa_stats ON uig.user_id = aqa_stats.answer_owner
LEFT JOIN (
    SELECT 
        UserId,
        COUNT(*) AS edit_count
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4, 5, 6)
    GROUP BY UserId
) ph_stats ON uig.user_id = ph_stats.UserId
WHERE uig.total_posts >= 5
  AND urt.reputation_decile <= 5
ORDER BY uig.tier, tier_rank
LIMIT 1000;