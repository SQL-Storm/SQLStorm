-- {"query": "16086.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 203145, "output_tokens": 188900} 

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
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS avg_answer_score,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 1 THEN 1 ELSE 0 END) AS questions_with_accepted_answers,
        ROW_NUMBER() OVER (PARTITION BY SUBSTRING(COALESCE(u.Location, 'Unknown'), 1, 20) ORDER BY u.Reputation DESC) AS location_rank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS post_volume_rank
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= TIMESTAMP '2018-01-01'
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
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        COALESCE(p.CommentCount, 0) AS comment_count,
        COALESCE(p.FavoriteCount, 0) AS favorite_count,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS upvote_count,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS downvote_count,
        (SELECT COUNT(DISTINCT ph.UserId) 
         FROM PostHistory ph 
         WHERE ph.PostId = p.Id 
           AND ph.PostHistoryTypeId IN (4, 5, 6)
           AND ph.UserId IS NOT NULL) AS unique_editors,
        LENGTH(COALESCE(p.Body, '')) AS body_length,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.AnswerCount > 0 THEN 'Has Answers'
            ELSE 'Unanswered'
        END AS post_status,
        EXTRACT(EPOCH FROM (COALESCE(p.LastActivityDate, p.CreationDate) - p.CreationDate)) / 86400.0 AS days_active
    FROM Posts p
    WHERE p.CreationDate >= TIMESTAMP '2019-01-01'
        AND p.PostTypeId IN (1, 2)
),
tag_expertise AS (
    SELECT 
        p.OwnerUserId,
        UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS tag_name,
        COUNT(*) AS tag_post_count,
        AVG(p.Score) AS avg_tag_score,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS accepted_in_tag
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.Tags IS NOT NULL
        AND LENGTH(p.Tags) > 2
    GROUP BY p.OwnerUserId, tag_name
    HAVING COUNT(*) >= 3
),
ranked_expertise AS (
    SELECT 
        te.OwnerUserId,
        te.tag_name,
        te.tag_post_count,
        te.avg_tag_score,
        ROW_NUMBER() OVER (PARTITION BY te.OwnerUserId ORDER BY te.tag_post_count DESC, te.avg_tag_score DESC) AS expertise_rank
    FROM tag_expertise te
)
SELECT 
    uam.DisplayName,
    uam.Reputation,
    uam.Location,
    uam.total_posts,
    uam.question_count,
    uam.answer_count,
    ROUND(COALESCE(uam.avg_question_score, 0)::numeric, 2) AS avg_question_score,
    ROUND(COALESCE(uam.avg_answer_score, 0)::numeric, 2) AS avg_answer_score,
    CASE 
        WHEN uam.question_count > 0 
        THEN ROUND((uam.questions_with_accepted_answers::numeric / uam.question_count::numeric * 100), 2)
        ELSE NULL
    END AS acceptance_rate_pct,
    COALESCE(ba.total_badges, 0) AS total_badges,
    COALESCE(ba.gold_badges, 0) AS gold_badges,
    COALESCE(ba.silver_badges, 0) AS silver_badges,
    COALESCE(ba.bronze_badges, 0) AS bronze_badges,
    COALESCE(ba.gold_badge_names, 'None') AS gold_badge_list,
    (SELECT STRING_AGG(re.tag_name, ', ') 
     FROM ranked_expertise re 
     WHERE re.OwnerUserId = uam.Id AND re.expertise_rank <= 3) AS top_3_tags,
    (SELECT AVG(pis.upvote_count::numeric / NULLIF(pis.upvote_count + pis.downvote_count, 0))
     FROM post_interaction_stats pis
     WHERE pis.OwnerUserId = uam.Id) AS avg_vote_ratio,
    (SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pis.ViewCount)
     FROM post_interaction_stats pis
     WHERE pis.OwnerUserId = uam.Id AND pis.PostTypeId = 1) AS median_question_views,
    uam.location_rank,
    uam.post_volume_rank,
    CASE 
        WHEN uam.Reputation >= 10000 THEN 'Elite'
        WHEN uam.Reputation >= 5000 THEN 'Advanced'
        WHEN uam.Reputation >= 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS user_tier,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - uam.CreationDate)) / 86400.0 AS account_age_days
FROM user_activity_metrics uam
LEFT OUTER JOIN badge_aggregates ba ON uam.Id = ba.UserId
WHERE uam.total_posts >= 5
    AND (ba.total_badges IS NULL OR ba.total_badges >= 1)
    AND uam.location_rank <= 10
    AND EXISTS (
        SELECT 1 
        FROM post_interaction_stats pis2 
        WHERE pis2.OwnerUserId = uam.Id 
            AND pis2.Score > 0
    )
ORDER BY 
    uam.Reputation DESC,
    uam.total_posts DESC,
    COALESCE(ba.total_badges, 0) DESC
LIMIT 100;
