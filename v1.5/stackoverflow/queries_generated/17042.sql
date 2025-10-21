-- {"query": "17042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 100405, "output_tokens": 98491} 

WITH user_expertise AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as questions_asked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answers_given,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') FILTER (WHERE p.Tags IS NOT NULL) as all_tags,
        RANK() OVER (ORDER BY u.Reputation DESC) as reputation_rank,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) FILTER (WHERE p.Score IS NOT NULL) as median_post_score
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
hot_questions AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.CreationDate,
        p.Tags,
        COALESCE(p.Score, 0) * 1.5 + COALESCE(p.ViewCount, 0) * 0.001 + COALESCE(p.AnswerCount, 0) * 10 as hotness_score,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        LEAD(p.Title, 1, 'No next question') OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as next_title,
        FIRST_VALUE(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST) as best_post_date
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.ClosedDate IS NULL
        AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND Score IS NOT NULL)
),
badge_analysis AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) as gold_badges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) as silver_badges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) as bronze_badges,
        MAX(CASE WHEN b.TagBased = '1' THEN b.Name END) as latest_tag_badge,
        DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) as badge_rank
    FROM Badges b
    GROUP BY b.UserId
),
complex_activity AS (
    SELECT DISTINCT
        ph.PostId,
        ph.UserId as editor_id,
        COUNT(*) OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId) as edit_frequency,
        STRING_AGG(
            CASE 
                WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 'Edit'
                WHEN ph.PostHistoryTypeId IN (7,8,9) THEN 'Rollback'
                WHEN ph.PostHistoryTypeId = 10 THEN 'Closed'
                WHEN ph.PostHistoryTypeId = 11 THEN 'Reopened'
                ELSE 'Other'
            END, ' -> '
        ) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as action_sequence
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId NOT IN (25, 31, 50, 52, 53)
)
SELECT 
    ue.DisplayName,
    ue.Reputation,
    ue.reputation_rank,
    COALESCE(ue.questions_asked, 0) + COALESCE(ue.answers_given, 0) as total_contributions,
    ROUND(CAST(COALESCE(ue.median_post_score, 0) AS numeric), 2) as median_score,
    COALESCE(ba.gold_badges, 0) || '/' || COALESCE(ba.silver_badges, 0) || '/' || COALESCE(ba.bronze_badges, 0) as badge_count,
    COALESCE(ba.latest_tag_badge, 'No tag badges') as latest_tag_badge,
    hq.Title as best_hot_question,
    ROUND(CAST(COALESCE(hq.hotness_score, 0) AS numeric), 2) as hotness_score,
    CASE 
        WHEN hq.prev_score IS NULL THEN 'First Question'
        WHEN hq.Score > hq.prev_score THEN 'Improving ↑'
        WHEN hq.Score < hq.prev_score THEN 'Declining ↓'
        ELSE 'Stable ='
    END as score_trend,
    SUBSTRING(COALESCE(hq.next_title, 'No next question'), 1, 50) || 
        CASE WHEN LENGTH(COALESCE(hq.next_title, '')) > 50 THEN '...' ELSE '' END as next_question_preview,
    (
        SELECT COUNT(DISTINCT v.PostId)
        FROM Votes v
        INNER JOIN Posts p2 ON v.PostId = p2.Id
        WHERE v.VoteTypeId = 2 
            AND p2.OwnerUserId = ue.Id
            AND v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    ) as recent_upvotes_received,
    EXISTS (
        SELECT 1 
        FROM Comments c
        WHERE c.UserId = ue.Id 
            AND c.Score > 5
            AND c.Text LIKE '%thank%' OR c.Text LIKE '%helpful%'
    ) as has_helpful_comments,
    COALESCE(ca.action_sequence, 'No edits') as last_post_edit_pattern,
    CASE 
        WHEN ue.Reputation > 10000 AND ba.gold_badges > 0 THEN 'Expert'
        WHEN ue.Reputation > 5000 OR ba.silver_badges > 2 THEN 'Advanced'
        WHEN ue.Reputation > 1000 THEN 'Intermediate'
        WHEN ue.Reputation > 100 THEN 'Beginner'
        ELSE 'Newcomer'
    END as user_level,
    COALESCE(
        NULLIF(
            TRIM(
                SUBSTRING(
                    ue.all_tags, 
                    1, 
                    CASE 
                        WHEN POSITION(',' IN ue.all_tags) > 0 
                        THEN POSITION(',' IN ue.all_tags) - 1 
                        ELSE LENGTH(ue.all_tags) 
                    END
                )
            ), 
            ''
        ),
        'No tags'
    ) as primary_tag
FROM user_expertise ue
LEFT OUTER JOIN badge_analysis ba ON ue.Id = ba.UserId
LEFT OUTER JOIN hot_questions hq ON ue.Id = hq.OwnerUserId 
    AND hq.best_post_date = hq.CreationDate
LEFT OUTER JOIN complex_activity ca ON hq.Id = ca.PostId 
    AND ca.edit_frequency = (
        SELECT MAX(edit_frequency) 
        FROM complex_activity ca2 
        WHERE ca2.PostId = hq.Id
    )
WHERE ue.reputation_rank <= 100
    AND (ba.badge_rank IS NULL OR ba.badge_rank <= 500)
    AND NOT (ue.questions_asked = 0 AND ue.answers_given = 0)
ORDER BY 
    CASE 
        WHEN hq.hotness_score IS NULL THEN 1 
        ELSE 0 
    END,
    hq.hotness_score DESC NULLS LAST,
    ue.reputation_rank,
    ba.gold_badges DESC NULLS LAST
LIMIT 50;
