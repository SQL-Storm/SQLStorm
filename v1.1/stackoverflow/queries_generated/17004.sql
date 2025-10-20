-- {"query": "17004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 11675, "output_tokens": 11897} 

WITH user_activity_stats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT c.Id) as comment_count,
        COALESCE(SUM(p.Score), 0) as total_post_score,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) as avg_post_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) FILTER (WHERE p.Score IS NOT NULL) as median_post_score,
        MAX(p.CreationDate) as last_post_date,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') FILTER (WHERE p.Tags IS NOT NULL) as all_tags_used
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
elite_users AS (
    SELECT 
        Id,
        DisplayName,
        Reputation,
        post_count,
        comment_count,
        total_post_score,
        avg_post_score,
        median_post_score,
        RANK() OVER (ORDER BY Reputation DESC) as reputation_rank,
        DENSE_RANK() OVER (ORDER BY total_post_score DESC NULLS LAST) as score_rank,
        ROW_NUMBER() OVER (PARTITION BY CASE 
            WHEN Reputation >= 10000 THEN 'Expert'
            WHEN Reputation >= 1000 THEN 'Advanced'
            WHEN Reputation >= 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END ORDER BY avg_post_score DESC NULLS LAST) as tier_rank,
        LEAD(DisplayName) OVER (ORDER BY Reputation DESC) as next_user_by_rep,
        LAG(DisplayName) OVER (ORDER BY Reputation DESC) as prev_user_by_rep,
        last_post_date,
        all_tags_used
    FROM user_activity_stats
    WHERE post_count > 0 OR comment_count > 0
),
question_answer_pairs AS (
    SELECT 
        q.Id as question_id,
        q.Title,
        q.OwnerUserId as asker_id,
        a.Id as answer_id,
        a.OwnerUserId as answerer_id,
        a.Score as answer_score,
        q.AcceptedAnswerId,
        CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END as is_accepted,
        a.CreationDate - q.CreationDate as response_time,
        FIRST_VALUE(a.Id) OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate) as best_answer_id,
        COUNT(*) OVER (PARTITION BY q.Id) as total_answers
    FROM Posts q
    INNER JOIN Posts a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1 
        AND a.PostTypeId = 2
        AND q.ClosedDate IS NULL
        AND a.Score >= 0
),
recursive_badge_chains AS (
    WITH RECURSIVE badge_hierarchy AS (
        SELECT 
            b1.UserId,
            b1.Name as badge_name,
            b1.Class as badge_class,
            b1.Date as badge_date,
            1 as chain_length,
            ARRAY[b1.Name] as badge_path,
            b1.Id as root_badge_id
        FROM Badges b1
        WHERE b1.Class = 1
        
        UNION ALL
        
        SELECT 
            b2.UserId,
            b2.Name,
            b2.Class,
            b2.Date,
            bh.chain_length + 1,
            bh.badge_path || b2.Name,
            bh.root_badge_id
        FROM badge_hierarchy bh
        INNER JOIN Badges b2 
            ON bh.UserId = b2.UserId 
            AND b2.Date > bh.badge_date
            AND b2.Class >= bh.badge_class
        WHERE bh.chain_length < 5
            AND NOT (b2.Name = ANY(bh.badge_path))
    )
    SELECT 
        UserId,
        MAX(chain_length) as max_badge_chain,
        STRING_AGG(DISTINCT badge_name, ' -> ' ORDER BY badge_date) FILTER (WHERE chain_length = (SELECT MAX(chain_length) FROM badge_hierarchy bh2 WHERE bh2.UserId = badge_hierarchy.UserId)) as longest_chain
    FROM badge_hierarchy
    GROUP BY UserId
)
SELECT 
    eu.DisplayName,
    COALESCE(eu.Reputation, 0) as reputation,
    CASE 
        WHEN eu.Reputation >= 10000 THEN 'Expert'
        WHEN eu.Reputation >= 1000 THEN 'Advanced'
        WHEN eu.Reputation >= 100 THEN 'Intermediate'
        ELSE 'Beginner'
    END as user_tier,
    eu.reputation_rank,
    eu.score_rank,
    COALESCE(eu.post_count, 0) + COALESCE(eu.comment_count, 0) as total_contributions,
    ROUND(COALESCE(eu.avg_post_score, 0)::numeric, 2) as avg_score,
    COALESCE(eu.median_post_score, 0) as median_score,
    COALESCE(LEFT(eu.all_tags_used, 100), 'No tags') as top_tags_preview,
    COALESCE(rbc.max_badge_chain, 0) as badge_achievement_chain,
    SUBSTRING(COALESCE(rbc.longest_chain, 'No badges'), 1, 50) as badge_progression,
    (
        SELECT COUNT(DISTINCT qap.question_id)
        FROM question_answer_pairs qap
        WHERE qap.answerer_id = eu.Id 
            AND qap.is_accepted = 1
    ) as accepted_answers_count,
    (
        SELECT COALESCE(AVG(EXTRACT(EPOCH FROM qap.response_time) / 3600.0), 0)
        FROM question_answer_pairs qap
        WHERE qap.answerer_id = eu.Id
            AND qap.response_time IS NOT NULL
            AND qap.response_time < INTERVAL '7 days'
    )::numeric(10, 2) as avg_response_time_hours,
    COALESCE(
        (
            SELECT STRING_AGG(DISTINCT ph.Comment, '; ')
            FROM PostHistory ph
            WHERE ph.UserId = eu.Id
                AND ph.PostHistoryTypeId IN (24, 16, 14)
                AND ph.Comment IS NOT NULL
                AND LENGTH(ph.Comment) > 0
            LIMIT 3
        ),
        'No special activities'
    ) as notable_activities,
    eu.prev_user_by_rep || ' <- [' || eu.DisplayName || '] -> ' || eu.next_user_by_rep as reputation_neighbors,
    CASE 
        WHEN eu.last_post_date IS NULL THEN 'Never posted'
        WHEN eu.last_post_date > CURRENT_DATE - INTERVAL '7 days' THEN 'Active this week'
        WHEN eu.last_post_date > CURRENT_DATE - INTERVAL '30 days' THEN 'Active this month'
        WHEN eu.last_post_date > CURRENT_DATE - INTERVAL '90 days' THEN 'Active this quarter'
        ELSE 'Inactive'
    END as activity_status,
    EXISTS (
        SELECT 1 
        FROM Votes v 
        WHERE v.UserId = eu.Id 
            AND v.VoteTypeId = 8
            AND v.BountyAmount > 100
    ) as is_generous_bounty_giver
FROM elite_users eu
LEFT JOIN recursive_badge_chains rbc ON eu.Id = rbc.UserId
WHERE eu.reputation_rank <= 1000
    OR eu.score_rank <= 500
    OR (eu.tier_rank = 1 AND eu.post_count >= 10)
    OR EXISTS (
        SELECT 1
        FROM question_answer_pairs qap2
        WHERE qap2.answerer_id = eu.Id
            AND qap2.best_answer_id = qap2.answer_id
            AND qap2.total_answers >= 5
    )
ORDER BY 
    COALESCE(eu.Reputation, 0) * 0.4 + 
    COALESCE(eu.total_post_score, 0) * 0.3 + 
    COALESCE(eu.post_count, 0) * 10 * 0.2 +
    COALESCE(rbc.max_badge_chain, 0) * 100 * 0.1 DESC
LIMIT 100;
