-- {"query": "16027.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 65380, "output_tokens": 61297} 

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
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS avg_question_score,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 1 THEN 1 ELSE 0 END) AS questions_with_accepted_answers,
        ROW_NUMBER() OVER (PARTITION BY SUBSTRING(COALESCE(u.Location, 'Unknown'), 1, 20) ORDER BY u.Reputation DESC) AS location_rank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS post_volume_rank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= '2018-01-01'
        AND (u.Reputation > 100 OR u.UpVotes > 10)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
    HAVING COUNT(DISTINCT p.Id) > 0
),
badge_aggregates AS (
    SELECT 
        b.UserId,
        COUNT(*) AS total_badges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 1 THEN b.Name END, ', ') AS gold_badge_names,
        MAX(b.Date) AS last_badge_date,
        MIN(b.Date) AS first_badge_date
    FROM Badges b
    WHERE b.TagBased = 0
    GROUP BY b.UserId
),
voting_patterns AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT v.Id) AS total_votes_received,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes_received,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes_received,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS total_bounty_earned,
        AVG(CASE WHEN v.VoteTypeId IN (2, 3) THEN 
            EXTRACT(EPOCH FROM (v.CreationDate - p.CreationDate))/3600.0 
        END) AS avg_hours_to_vote
    FROM Posts p
    INNER JOIN Votes v ON p.Id = v.PostId
    WHERE p.OwnerUserId IS NOT NULL
        AND v.VoteTypeId IN (2, 3, 8)
    GROUP BY p.OwnerUserId
),
comment_engagement AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT c.Id) AS comments_on_posts,
        AVG(c.Score) AS avg_comment_score,
        COUNT(DISTINCT c.UserId) AS unique_commenters,
        MAX(LENGTH(c.Text)) AS max_comment_length
    FROM Posts p
    INNER JOIN Comments c ON p.Id = c.PostId
    WHERE c.UserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
post_history_stats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT ph.Id) AS total_edits,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS user_edits,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS posts_closed,
        AVG(CASE WHEN ph.Text IS NOT NULL THEN LENGTH(ph.Text) ELSE 0 END) AS avg_revision_length
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
answer_acceptance_rate AS (
    SELECT 
        a.OwnerUserId,
        COUNT(*) AS total_answers,
        SUM(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS accepted_answers,
        CASE 
            WHEN COUNT(*) > 0 THEN 
                ROUND(100.0 * SUM(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) / COUNT(*), 2)
            ELSE NULL 
        END AS acceptance_rate
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2 
        AND a.OwnerUserId IS NOT NULL
    GROUP BY a.OwnerUserId
)
SELECT 
    uam.Id AS user_id,
    uam.DisplayName,
    uam.Location,
    uam.Reputation,
    uam.total_posts,
    uam.question_count,
    uam.answer_count,
    COALESCE(ROUND(uam.avg_question_score::numeric, 2), 0) AS avg_question_score,
    uam.questions_with_accepted_answers,
    COALESCE(ba.total_badges, 0) AS total_badges,
    COALESCE(ba.gold_badges, 0) AS gold_badges,
    COALESCE(ba.silver_badges, 0) AS silver_badges,
    COALESCE(ba.bronze_badges, 0) AS bronze_badges,
    COALESCE(ba.gold_badge_names, 'None') AS gold_badge_list,
    COALESCE(vp.upvotes_received, 0) AS upvotes_received,
    COALESCE(vp.downvotes_received, 0) AS downvotes_received,
    CASE 
        WHEN COALESCE(vp.upvotes_received, 0) + COALESCE(vp.downvotes_received, 0) > 0 THEN
            ROUND(100.0 * COALESCE(vp.upvotes_received, 0) / 
                (COALESCE(vp.upvotes_received, 0) + COALESCE(vp.downvotes_received, 0)), 2)
        ELSE NULL
    END AS upvote_percentage,
    COALESCE(vp.total_bounty_earned, 0) AS total_bounty_earned,
    COALESCE(ROUND(vp.avg_hours_to_vote::numeric, 2), 0) AS avg_hours_to_vote,
    COALESCE(ce.comments_on_posts, 0) AS comments_received,
    COALESCE(ce.unique_commenters, 0) AS unique_commenters,
    COALESCE(ROUND(ce.avg_comment_score::numeric, 2), 0) AS avg_comment_score,
    COALESCE(phs.total_edits, 0) AS total_edits,
    COALESCE(phs.posts_closed, 0) AS posts_closed,
    COALESCE(aar.acceptance_rate, 0) AS answer_acceptance_rate,
    uam.location_rank,
    uam.post_volume_rank,
    CASE 
        WHEN uam.question_count > 0 THEN 
            ROUND(100.0 * uam.questions_with_accepted_answers / uam.question_count, 2)
        ELSE NULL 
    END AS question_resolution_rate,
    EXTRACT(DAYS FROM (CURRENT_TIMESTAMP - uam.CreationDate)) AS days_since_joined,
    (SELECT COUNT(*) 
     FROM PostLinks pl 
     INNER JOIN Posts p2 ON pl.PostId = p2.Id 
     WHERE p2.OwnerUserId = uam.Id AND pl.LinkTypeId = 3) AS duplicate_posts_count
FROM user_activity_metrics uam
LEFT OUTER JOIN badge_aggregates ba ON uam.Id = ba.UserId
LEFT OUTER JOIN voting_patterns vp ON uam.Id = vp.OwnerUserId
LEFT OUTER JOIN comment_engagement ce ON uam.Id = ce.OwnerUserId
LEFT OUTER JOIN post_history_stats phs ON uam.Id = phs.OwnerUserId
LEFT OUTER JOIN answer_acceptance_rate aar ON uam.Id = aar.OwnerUserId
WHERE (uam.location_rank <= 5 OR uam.post_volume_rank <= 100)
    AND (ba.total_badges >= 5 OR vp.upvotes_received >= 50 OR uam.answer_count >= 10)
    AND NOT EXISTS (
        SELECT 1 FROM Posts p3 
        WHERE p3.OwnerUserId = uam.Id 
            AND p3.ClosedDate IS NOT NULL 
        HAVING COUNT(*) > 5
    )
ORDER BY 
    CASE 
        WHEN uam.Reputation > 10000 THEN 1
        WHEN uam.Reputation > 1000 THEN 2
        ELSE 3
    END,
    COALESCE(vp.upvotes_received, 0) DESC,
    uam.total_posts DESC
LIMIT 500;
