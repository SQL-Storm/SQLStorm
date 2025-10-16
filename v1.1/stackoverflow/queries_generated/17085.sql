-- {"query": "17085.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 200810, "output_tokens": 198698} 

WITH user_activity_stats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answer_count,
        COALESCE(AVG(p.Score), 0) as avg_post_score,
        MAX(p.CreationDate) as last_post_date,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as reputation_rank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as activity_rank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
tag_expertise AS (
    SELECT 
        p.OwnerUserId,
        TRIM(BOTH '<>' FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))) as tag_name,
        COUNT(*) as tag_post_count,
        SUM(p.Score) as total_tag_score,
        AVG(p.Score) as avg_tag_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_tag_score
    FROM Posts p
    WHERE p.Tags IS NOT NULL 
        AND p.OwnerUserId IS NOT NULL
        AND p.PostTypeId IN (1, 2)
    GROUP BY p.OwnerUserId, tag_name
),
top_tag_experts AS (
    SELECT 
        te.*,
        t.Count as global_tag_count,
        ROW_NUMBER() OVER (PARTITION BY te.tag_name ORDER BY te.total_tag_score DESC) as expert_rank
    FROM tag_expertise te
    INNER JOIN Tags t ON te.tag_name = t.TagName
    WHERE te.tag_post_count >= 5
),
badge_achievements AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) as gold_badges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) as silver_badges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) as bronze_badges,
        STRING_AGG(CASE WHEN b.Class = 1 THEN b.Name END, ', ' ORDER BY b.Date DESC) as gold_badge_names,
        MAX(b.Date) as last_badge_date
    FROM Badges b
    GROUP BY b.UserId
),
edit_history AS (
    SELECT 
        ph.UserId,
        COUNT(DISTINCT ph.PostId) as edited_posts,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) as edit_count,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (7, 8, 9) THEN 1 END) as rollback_count,
        FIRST_VALUE(ph.CreationDate) OVER (
            PARTITION BY ph.UserId 
            ORDER BY ph.CreationDate DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) as last_edit_date
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
interaction_network AS (
    SELECT 
        p1.OwnerUserId as user_id,
        p2.OwnerUserId as interacted_user_id,
        COUNT(DISTINCT c.Id) as comment_interactions,
        COUNT(DISTINCT CASE WHEN p2.AcceptedAnswerId = p1.Id THEN p2.Id END) as accepted_answers,
        COUNT(DISTINCT v.Id) as vote_interactions
    FROM Posts p1
    INNER JOIN Comments c ON p1.Id = c.PostId AND c.UserId != p1.OwnerUserId
    LEFT JOIN Posts p2 ON p2.Id = p1.ParentId OR p1.Id = p2.ParentId
    LEFT JOIN Votes v ON p1.Id = v.PostId AND v.UserId != p1.OwnerUserId
    WHERE p1.OwnerUserId IS NOT NULL 
        AND p2.OwnerUserId IS NOT NULL
        AND p1.OwnerUserId != p2.OwnerUserId
    GROUP BY p1.OwnerUserId, p2.OwnerUserId
)
SELECT 
    uas.DisplayName,
    uas.Reputation,
    uas.reputation_rank,
    uas.post_count,
    uas.question_count,
    uas.answer_count,
    ROUND(uas.avg_post_score::numeric, 2) as avg_post_score,
    CASE 
        WHEN uas.question_count > 0 AND uas.answer_count > 0 
        THEN ROUND((uas.answer_count::numeric / NULLIF(uas.question_count, 0)), 2)
        ELSE NULL 
    END as answer_to_question_ratio,
    EXTRACT(DAY FROM CURRENT_TIMESTAMP - uas.last_post_date) as days_since_last_post,
    COALESCE(ba.gold_badges, 0) + COALESCE(ba.silver_badges, 0) * 0.5 + COALESCE(ba.bronze_badges, 0) * 0.1 as badge_score,
    SUBSTRING(COALESCE(ba.gold_badge_names, 'No gold badges'), 1, 100) as gold_badges_earned,
    COALESCE(eh.edit_count, 0) as total_edits,
    CASE 
        WHEN COALESCE(eh.edit_count, 0) > 0 
        THEN ROUND(100.0 * COALESCE(eh.rollback_count, 0) / eh.edit_count, 2)
        ELSE 0 
    END as rollback_percentage,
    (
        SELECT STRING_AGG(
            tte.tag_name || ' (score: ' || tte.total_tag_score || ')', 
            ', ' 
            ORDER BY tte.total_tag_score DESC
        )
        FROM top_tag_experts tte
        WHERE tte.OwnerUserId = uas.Id 
            AND tte.expert_rank <= 3
        LIMIT 5
    ) as top_expertise_tags,
    (
        SELECT COUNT(DISTINCT interacted_user_id)
        FROM interaction_network intn
        WHERE intn.user_id = uas.Id
    ) as unique_user_interactions,
    CASE 
        WHEN uas.Reputation > 10000 AND ba.gold_badges > 5 THEN 'Elite Contributor'
        WHEN uas.Reputation > 5000 OR ba.gold_badges > 2 THEN 'Veteran'
        WHEN uas.Reputation > 1000 THEN 'Active Member'
        WHEN uas.post_count > 10 THEN 'Regular'
        ELSE 'Newcomer'
    END as user_tier,
    COALESCE(
        (
            SELECT AVG(p.Score)
            FROM Posts p
            WHERE p.OwnerUserId = uas.Id
                AND p.CreationDate > CURRENT_TIMESTAMP - INTERVAL '90 days'
        ), 0
    ) as recent_avg_score,
    EXISTS (
        SELECT 1
        FROM Posts p
        WHERE p.OwnerUserId = uas.Id
            AND p.Score >= 100
    ) as has_great_post
FROM user_activity_stats uas
LEFT JOIN badge_achievements ba ON uas.Id = ba.UserId
LEFT JOIN edit_history eh ON uas.Id = eh.UserId
WHERE uas.reputation_rank <= 1000
    AND (uas.post_count > 20 OR ba.gold_badges > 0)
    AND uas.last_post_date > CURRENT_TIMESTAMP - INTERVAL '2 years'
ORDER BY 
    CASE 
        WHEN ba.gold_badges IS NULL THEN 1 
        ELSE 0 
    END,
    uas.Reputation * POWER(COALESCE(ba.gold_badges, 0) + 1, 1.5) * 
    (1 + LOG(GREATEST(uas.post_count, 1))) * 
    COALESCE(NULLIF(uas.avg_post_score, 0), 1) DESC,
    uas.DisplayName ASC
LIMIT 100;
