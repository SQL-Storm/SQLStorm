-- {"query": "16043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 2147}

WITH user_activity_metrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.Location, 'Unknown') AS Location,
        COUNT(DISTINCT p.Id) AS total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_count,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS avg_post_score,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 1 THEN 1 ELSE 0 END) AS questions_with_accepted_answers,
        ROW_NUMBER() OVER (PARTITION BY SUBSTRING(COALESCE(u.Location, 'Unknown'), 1, 20) ORDER BY u.Reputation DESC) AS location_rank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS post_count_rank,
        LAG(u.Reputation, 1, 0) OVER (ORDER BY u.CreationDate) AS prev_user_reputation,
        LEAD(u.CreationDate, 1) OVER (ORDER BY u.CreationDate) AS next_user_creation_date
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 100
        AND u.CreationDate >= '2020-01-01'
        AND (u.Location IS NULL OR LENGTH(TRIM(u.Location)) > 0)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
    HAVING COUNT(DISTINCT p.Id) > 0
),
badge_aggregates AS (
    SELECT 
        b.UserId,
        COUNT(*) AS total_badges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold_badges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver_badges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze_badges,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 1 THEN b.Name ELSE NULL END, ', ') AS gold_badge_names,
        MAX(b.Date) AS latest_badge_date,
        MIN(b.Date) AS first_badge_date
    FROM Badges b
    WHERE b.TagBased = 0
    GROUP BY b.UserId
),
post_interaction_stats AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        COUNT(DISTINCT c.Id) AS comment_count_manual,
        COUNT(DISTINCT v.Id) AS vote_count,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS upvote_count,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS downvote_count,
        MAX(c.CreationDate) AS last_comment_date,
        AVG(c.Score) AS avg_comment_score,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount, 0) ELSE 0 END) AS total_bounty_amount
    FROM Posts p
    LEFT OUTER JOIN Comments c ON p.Id = c.PostId
    LEFT OUTER JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2)
        AND p.CreationDate >= '2019-01-01'
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount
),
tag_expertise AS (
    SELECT 
        p.OwnerUserId,
        UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS tag_name,
        COUNT(*) AS tag_usage_count,
        AVG(p.Score) AS avg_score_for_tag,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS accepted_in_tag
    FROM Posts p
    WHERE p.PostTypeId = 1
        AND p.Tags IS NOT NULL
        AND LENGTH(p.Tags) > 2
    GROUP BY p.OwnerUserId, UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'))
)
SELECT 
    uam.DisplayName,
    uam.Reputation,
    uam.Location,
    uam.total_posts,
    uam.question_count,
    uam.answer_count,
    ROUND(uam.avg_post_score::numeric, 2) AS avg_post_score,
    uam.questions_with_accepted_answers,
    CASE 
        WHEN uam.question_count > 0 THEN ROUND((uam.questions_with_accepted_answers::numeric / uam.question_count::numeric) * 100, 2)
        ELSE 0
    END AS acceptance_rate,
    uam.location_rank,
    uam.post_count_rank,
    COALESCE(ba.total_badges, 0) AS total_badges,
    COALESCE(ba.gold_badges, 0) AS gold_badges,
    COALESCE(ba.silver_badges, 0) AS silver_badges,
    COALESCE(ba.bronze_badges, 0) AS bronze_badges,
    COALESCE(ba.gold_badge_names, 'None') AS gold_badge_list,
    (SELECT AVG(pis.vote_count) 
     FROM post_interaction_stats pis 
     WHERE pis.OwnerUserId = uam.Id) AS avg_votes_per_post,
    (SELECT COUNT(DISTINCT pl.RelatedPostId)
     FROM Posts p
     INNER JOIN PostLinks pl ON p.Id = pl.PostId
     WHERE p.OwnerUserId = uam.Id AND pl.LinkTypeId = 1) AS total_linked_posts,
    (SELECT STRING_AGG(DISTINCT te.tag_name, ', ')
     FROM tag_expertise te
     WHERE te.OwnerUserId = uam.Id
     ORDER BY te.tag_usage_count DESC
     LIMIT 5) AS top_tags,
    (SELECT MAX(te.avg_score_for_tag)
     FROM tag_expertise te
     WHERE te.OwnerUserId = uam.Id) AS best_tag_avg_score,
    EXTRACT(EPOCH FROM (COALESCE(uam.next_user_creation_date, CURRENT_TIMESTAMP) - uam.CreationDate)) / 86400 AS days_until_next_user,
    EXISTS(
        SELECT 1 
        FROM PostHistory ph
        WHERE ph.UserId = uam.Id
            AND ph.PostHistoryTypeId IN (24, 4, 5, 6)
    ) AS has_edit_history,
    (SELECT COUNT(*)
     FROM Posts p1
     WHERE p1.OwnerUserId = uam.Id
         AND p1.PostTypeId = 2
         AND EXISTS (
             SELECT 1
             FROM Posts p2
             WHERE p2.Id = p1.ParentId
                 AND p2.AcceptedAnswerId = p1.Id
         )) AS total_accepted_answers
FROM user_activity_metrics uam
LEFT OUTER JOIN badge_aggregates ba ON uam.Id = ba.UserId
WHERE uam.total_posts >= 5
    AND uam.location_rank <= 10
    AND (ba.total_badges IS NULL OR ba.total_badges > 0)
    AND uam.Reputation > (SELECT AVG(Reputation) FROM Users WHERE Reputation > 100)
ORDER BY 
    CASE 
        WHEN uam.Reputation > 10000 THEN uam.total_posts 
        ELSE uam.Reputation 
    END DESC,
    uam.avg_post_score DESC NULLS LAST,
    ba.gold_badges DESC NULLS LAST
LIMIT 100;
