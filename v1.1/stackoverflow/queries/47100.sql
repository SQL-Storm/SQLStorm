WITH RECURSIVE tag_hierarchy AS (
    -- base level: tags with initial aggregates computed from posts
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT p.Id) AS question_count,
        CAST(AVG(p.Score) AS double precision) AS avg_score,
        1 AS level
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE p.PostTypeId = 1
      AND t.Count > 1000
    GROUP BY t.Id, t.TagName

    UNION ALL

    -- recursive term: select related tags at row level (no aggregates)
    SELECT 
        t2.Id,
        t2.TagName,
        CAST(NULL AS bigint) AS question_count,
        CAST(NULL AS double precision) AS avg_score,
        th.level + 1
    FROM tag_hierarchy th
    JOIN Posts p1 ON p1.Tags LIKE '%' || '<' || th.TagName || '>' || '%'
    JOIN Posts p2 ON p2.Tags LIKE '%' || '<' || th.TagName || '>' || '%'
      AND p2.Id <> p1.Id
      AND p2.PostTypeId = 1
    JOIN Tags t2 ON p2.Tags LIKE '%' || '<' || t2.TagName || '>' || '%'
      AND t2.Id <> th.Id
    WHERE th.level < 3
    GROUP BY t2.Id, t2.TagName, th.level
),
tag_hierarchy_agg AS (
    SELECT
        th.Id,
        th.TagName,
        th.level,
        COUNT(DISTINCT p.Id) AS question_count,
        CAST(AVG(p.Score) AS double precision) AS avg_score
    FROM tag_hierarchy th
    JOIN Posts p ON p.Tags LIKE '%' || '<' || th.TagName || '>' || '%'
      AND p.PostTypeId = 1
    GROUP BY th.Id, th.TagName, th.level
),
user_expertise AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        string_agg(DISTINCT substring(p.Tags FROM 2 FOR (position('>' IN p.Tags) - 2)), ', ') AS primary_tags,
        COUNT(DISTINCT p.Id) AS total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answers,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.AcceptedAnswerId END) AS accepted_answers,
        CAST(AVG(p.Score) AS double precision) AS avg_post_score,
        SUM(p.Score) AS total_score,
        COUNT(DISTINCT b.Id) AS badge_count,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS gold_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS silver_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS bronze_badges,
        MAX(p.CreationDate) AS last_post_date,
        MIN(p.CreationDate) AS first_post_date,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS median_score,
        STDDEV(p.Score) AS score_stddev
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 10000
      AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years')
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 50
),
post_quality_metrics AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE 
            WHEN p.ViewCount > 0 THEN CAST(p.Score AS double precision) / p.ViewCount 
            ELSE 0 
        END AS score_per_view,
        CASE 
            WHEN p.AnswerCount > 0 THEN CAST(p.Score AS double precision) / p.AnswerCount 
            ELSE p.Score 
        END AS score_per_answer,
        COUNT(DISTINCT ph.Id) AS edit_count,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 12) THEN ph.Id END) AS close_delete_events,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (11, 13) THEN ph.Id END) AS reopen_undelete_events,
        COUNT(DISTINCT v.Id) AS vote_count,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS upvotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS downvotes,
        COUNT(DISTINCT c.Id) AS comment_count,
        AVG(c.Score) AS avg_comment_score,
        EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 86400 AS days_active,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS score_rank,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC) AS view_rank,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_post_score,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS next_post_score
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
      AND p.Score > 5
    GROUP BY p.Id, p.PostTypeId, p.Score, p.ViewCount, p.AnswerCount, 
             p.CommentCount, p.FavoriteCount, p.LastActivityDate, p.CreationDate, p.OwnerUserId
),
linked_post_network AS (
    SELECT 
        pl.PostId,
        pl.RelatedPostId,
        p1.Score AS source_score,
        p2.Score AS target_score,
        p1.ViewCount AS source_views,
        p2.ViewCount AS target_views,
        COUNT(*) OVER (PARTITION BY pl.PostId) AS outbound_links,
        COUNT(*) OVER (PARTITION BY pl.RelatedPostId) AS inbound_links,
        CASE 
            WHEN pl.LinkTypeId = 3 THEN 'Duplicate'
            WHEN pl.LinkTypeId = 1 THEN 'Linked'
            ELSE 'Other'
        END AS link_type,
        ABS(p1.Score - p2.Score) AS score_difference,
        CAST(GREATEST(p1.Score, p2.Score) AS double precision) / NULLIF(LEAST(p1.Score, p2.Score), 0) AS score_ratio
    FROM PostLinks pl
    JOIN Posts p1 ON pl.PostId = p1.Id
    JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    WHERE p1.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months')
      AND p2.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months')
)
SELECT 
    ue.DisplayName,
    ue.Reputation,
    ue.primary_tags,
    ue.total_posts,
    ue.questions,
    ue.answers,
    ue.accepted_answers,
    ROUND(CAST(ue.avg_post_score AS numeric), 2) AS avg_post_score,
    ue.total_score,
    ue.gold_badges,
    ue.silver_badges,
    ue.bronze_badges,
    ROUND(CAST(ue.median_score AS numeric), 2) AS median_score,
    ROUND(CAST(ue.score_stddev AS numeric), 2) AS score_stddev,
    COUNT(DISTINCT pqm.PostId) AS high_quality_posts,
    AVG(pqm.score_per_view) AS avg_score_per_view,
    AVG(pqm.edit_count) AS avg_edits_per_post,
    AVG(pqm.days_active) AS avg_days_active,
    COUNT(DISTINCT lpn.PostId) AS linked_posts,
    AVG(lpn.score_difference) AS avg_link_score_diff,
    -- fix: ORDER BY expressions inside STRING_AGG must appear in aggregation argument in many dialects;
    -- use STRING_AGG without ORDER BY and construct ordering via a subquery if needed. Here aggregate distinct tag names.
    STRING_AGG(DISTINCT th.TagName, ', ') AS related_tags,
    EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS timestamp) - ue.first_post_date)) AS days_on_platform,
    EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS timestamp) - ue.last_post_date)) AS days_since_last_post,
    CASE 
        WHEN ue.Reputation > 100000 THEN 'Legendary'
        WHEN ue.Reputation > 50000 THEN 'Epic'
        WHEN ue.Reputation > 25000 THEN 'Trusted'
        ELSE 'Established'
    END AS user_tier,
    ROUND((CAST(ue.accepted_answers AS double precision) / NULLIF(ue.answers, 0)) * 100, 2) AS acceptance_rate
FROM user_expertise ue
LEFT JOIN Posts p ON p.OwnerUserId = ue.UserId
LEFT JOIN post_quality_metrics pqm ON p.Id = pqm.PostId
LEFT JOIN linked_post_network lpn ON p.Id = lpn.PostId
LEFT JOIN tag_hierarchy_agg th ON p.Tags LIKE '%' || '<' || th.TagName || '>' || '%'
WHERE ue.avg_post_score > 10
  AND ue.total_posts > 100
GROUP BY 
    ue.DisplayName, ue.Reputation, ue.primary_tags, ue.total_posts,
    ue.questions, ue.answers, ue.accepted_answers, ue.avg_post_score,
    ue.total_score, ue.gold_badges, ue.silver_badges, ue.bronze_badges,
    ue.median_score, ue.score_stddev, ue.first_post_date, ue.last_post_date
HAVING COUNT(DISTINCT pqm.PostId) > 10
ORDER BY 
    ue.Reputation DESC,
    ue.avg_post_score DESC,
    ue.total_score DESC
LIMIT 100;