-- {"query": "51086.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 1104} 

WITH monthly_stats AS (
    SELECT 
        EXTRACT(YEAR FROM p.CreationDate) AS year,
        EXTRACT(MONTH FROM p.CreationDate) AS month,
        COUNT(DISTINCT u.Id) AS active_users,
        COUNT(p.Id) AS total_posts,
        SUM(CASE WHEN pt.Id = 1 THEN 1 ELSE 0 END) AS questions,
        SUM(CASE WHEN pt.Id = 2 THEN 1 ELSE 0 END) AS answers,
        AVG(u.Reputation) AS avg_user_reputation,
        SUM(v.BountyAmount) AS total_bounties,
        COUNT(DISTINCT CASE WHEN pt.Id = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) AS closed_questions,
        COUNT(DISTINCT CASE WHEN b.Name LIKE '%gold%' THEN b.Id END) AS gold_badges
    FROM Posts p
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (8, 9)
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY year, month
),
user_engagement AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS post_count,
        SUM(p.Score) AS total_score,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS upvotes_received,
        AVG(DATE_PART('day', p.LastActivityDate - p.CreationDate)) AS avg_post_lifespan,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS gold_badges_earned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS total_question_views
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 2
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
tag_performance AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS question_count,
        AVG(p.Score) AS avg_question_score,
        SUM(p.ViewCount) AS total_views,
        COUNT(DISTINCT CASE WHEN p.ClosedDate IS NOT NULL THEN p.Id END) AS closed_count,
        AVG(p.AnswerCount) AS avg_answers_per_question,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.Id END) * 100.0 / NULLIF(COUNT(DISTINCT p.Id), 0) AS acceptance_rate
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 50
),
social_network AS (
    SELECT 
        u1.Id AS user1_id,
        u2.Id AS user2_id,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.Id END) AS link_count,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.Id END) AS duplicate_count,
        AVG(DATE_PART('day', pl.CreationDate - GREATEST(p1.CreationDate, p2.CreationDate))) AS avg_link_delay
    FROM Users u1
    JOIN Posts p1 ON u1.Id = p1.OwnerUserId
    JOIN PostLinks pl ON p1.Id = pl.PostId
    JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    JOIN Users u2 ON p2.OwnerUserId = u2.Id
    WHERE u1.Id < u2.Id
    GROUP BY u1.Id, u2.Id
    HAVING COUNT(DISTINCT pl.Id) >= 3
)
SELECT 
    ms.year,
    ms.month,
    ms.active_users,
    ms.total_posts,
    ms.questions,
    ms.answers,
    ms.questions * 1.0 / NULLIF(ms.questions + ms.answers, 0) AS question_answer_ratio,
    ue.engagement_score,
    tp.high_performing_tags,
    sn.connected_users
FROM monthly_stats ms
CROSS JOIN (
    SELECT 
        AVG(total_score + post_count * 10 + gold_badges_earned * 50) AS engagement_score
    FROM user_engagement
) ue
CROSS JOIN (
    SELECT 
        COUNT(CASE WHEN avg_question_score > 5 AND acceptance_rate > 30 THEN 1 END) AS high_performing_tags
    FROM tag_performance
) tp
CROSS JOIN (
    SELECT 
        COUNT(DISTINCT user1_id) + COUNT(DISTINCT user2_id) AS connected_users
    FROM social_network
) sn
WHERE ms.year >= 2020
ORDER BY ms.year DESC, ms.month DESC
LIMIT 24;
