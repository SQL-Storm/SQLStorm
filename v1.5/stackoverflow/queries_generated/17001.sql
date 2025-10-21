-- {"query": "17001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 4670, "output_tokens": 4794} 

WITH user_activity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answer_count,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score END) as avg_post_score,
        MAX(p.Score) as max_post_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_score
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
badge_rankings AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) as gold_badges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) as silver_badges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) as bronze_badges,
        STRING_AGG(DISTINCT CASE WHEN Class = 1 THEN Name END, ', ' ORDER BY Name) as gold_badge_names,
        DENSE_RANK() OVER (ORDER BY COUNT(CASE WHEN Class = 1 THEN 1 END) DESC) as gold_rank,
        ROW_NUMBER() OVER (PARTITION BY Class ORDER BY Date DESC) as recent_badge_rank
    FROM Badges
    GROUP BY UserId
),
tag_expertise AS (
    SELECT 
        p.OwnerUserId,
        UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag,
        COUNT(*) as tag_posts,
        SUM(p.Score) as tag_score,
        AVG(CASE WHEN p.ViewCount > 0 THEN LOG(p.ViewCount + 1) END) as log_avg_views
    FROM Posts p
    WHERE p.Tags IS NOT NULL 
        AND p.OwnerUserId IS NOT NULL
        AND p.PostTypeId = 1
    GROUP BY p.OwnerUserId, tag
),
top_tag_experts AS (
    SELECT 
        te.*,
        t.Count as global_tag_count,
        RANK() OVER (PARTITION BY te.tag ORDER BY te.tag_score DESC NULLS LAST) as tag_rank,
        te.tag_score::float / NULLIF(t.Count, 0) as relative_expertise
    FROM tag_expertise te
    LEFT JOIN Tags t ON te.tag = t.TagName
    WHERE te.tag_posts >= 5
),
edit_patterns AS (
    SELECT 
        ph.UserId,
        COUNT(DISTINCT ph.PostId) as edited_posts,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 END) as edit_count,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (7,8,9) THEN 1 END) as rollback_count,
        AVG(LENGTH(COALESCE(ph.Text, ''))) as avg_edit_length,
        EXTRACT(DOW FROM ph.CreationDate) as edit_day_of_week,
        COUNT(*) FILTER (WHERE ph.CreationDate::time BETWEEN '00:00:00' AND '06:00:00') as night_edits
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId, EXTRACT(DOW FROM ph.CreationDate)
),
complex_post_metrics AS (
    SELECT 
        q.Id as question_id,
        q.Title,
        q.OwnerUserId as asker_id,
        a.Id as answer_id,
        a.OwnerUserId as answerer_id,
        q.Score as q_score,
        a.Score as a_score,
        CASE 
            WHEN q.AcceptedAnswerId = a.Id THEN 'accepted'
            WHEN a.Score > COALESCE((
                SELECT MAX(a2.Score) 
                FROM Posts a2 
                WHERE a2.ParentId = q.Id 
                    AND a2.Id != a.Id
            ), -999) THEN 'highest_scored'
            ELSE 'regular'
        END as answer_status,
        COALESCE(q.ViewCount, 0) / NULLIF(EXTRACT(DAY FROM (CURRENT_TIMESTAMP - q.CreationDate)), 0) as views_per_day,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id AND c.Score > 0) as positive_comments,
        EXISTS(
            SELECT 1 
            FROM PostHistory ph 
            WHERE ph.PostId = a.Id 
                AND ph.PostHistoryTypeId = 10
        ) as was_closed,
        LAG(a.Score, 1) OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate) as prev_answer_score,
        FIRST_VALUE(a.CreationDate) OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate) as first_answer_time
    FROM Posts q
    INNER JOIN Posts a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1 
        AND a.PostTypeId = 2
        AND q.Score >= 0
        AND q.AnswerCount > 0
)
SELECT 
    ua.DisplayName,
    ua.Reputation,
    COALESCE(ua.question_count, 0) + COALESCE(ua.answer_count, 0) as total_posts,
    ROUND(ua.avg_post_score::numeric, 2) as avg_score,
    COALESCE(br.gold_badges, 0) || '/' || COALESCE(br.silver_badges, 0) || '/' || COALESCE(br.bronze_badges, 0) as badge_summary,
    SUBSTRING(COALESCE(br.gold_badge_names, 'None'), 1, 50) as top_gold_badges,
    (
        SELECT STRING_AGG(tag || ':' || tag_score, ', ' ORDER BY tag_score DESC)
        FROM (
            SELECT DISTINCT tag, tag_score 
            FROM top_tag_experts tte 
            WHERE tte.OwnerUserId = ua.Id 
                AND tte.tag_rank <= 10
            LIMIT 3
        ) top_tags
    ) as top_3_tags,
    COALESCE(
        (
            SELECT AVG(cpm.a_score)
            FROM complex_post_metrics cpm
            WHERE cpm.answerer_id = ua.Id
                AND cpm.answer_status IN ('accepted', 'highest_scored')
                AND cpm.views_per_day > 10
        ), 0
    )::numeric(10,2) as avg_quality_answer_score,
    (
        SELECT COUNT(DISTINCT v.PostId)
        FROM Votes v
        INNER JOIN Posts p ON v.PostId = p.Id
        WHERE v.UserId = ua.Id
            AND v.VoteTypeId = 2
            AND p.OwnerUserId != ua.Id
            AND p.Score < 0
    ) as upvoted_negative_posts,
    CASE 
        WHEN ua.Reputation > 50000 THEN 'Elite'
        WHEN ua.Reputation > 10000 THEN 'Expert'
        WHEN ua.Reputation > 5000 THEN 'Trusted'
        WHEN ua.Reputation > 2000 THEN 'Established'
        ELSE 'Active'
    END as user_tier,
    COALESCE(
        (
            SELECT MAX(ep.edit_count)
            FROM edit_patterns ep
            WHERE ep.UserId = ua.Id
                AND ep.edit_day_of_week IN (0, 6)
        ), 0
    ) as max_weekend_edits,
    GREATEST(
        0,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - ua.Reputation * INTERVAL '1 minute')) / 86400
    )::int as pseudo_age_days
FROM user_activity ua
LEFT JOIN badge_rankings br ON ua.Id = br.UserId
WHERE ua.post_count > 10
    AND (br.gold_badges > 0 OR ua.max_post_score > 100)
    AND ua.DisplayName IS NOT NULL
    AND LENGTH(ua.DisplayName) > 3
    AND NOT EXISTS (
        SELECT 1
        FROM Posts p
        WHERE p.OwnerUserId = ua.Id
            AND p.ClosedDate IS NOT NULL
            AND p.Score < -5
    )
UNION ALL
SELECT 
    'SYSTEM_AVERAGE' as DisplayName,
    AVG(Reputation)::int as Reputation,
    AVG(question_count + answer_count)::int as total_posts,
    AVG(avg_post_score)::numeric(10,2) as avg_score,
    NULL as badge_summary,
    NULL as top_gold_badges,
    NULL as top_3_tags,
    NULL as avg_quality_answer_score,
    NULL as upvoted_negative_posts,
    'AGGREGATE' as user_tier,
    NULL as max_weekend_edits,
    NULL as pseudo_age_days
FROM user_activity
WHERE question_count + answer_count > 10
ORDER BY 
    CASE WHEN DisplayName = 'SYSTEM_AVERAGE' THEN 1 ELSE 0 END,
    Reputation DESC NULLS LAST,
    total_posts DESC
LIMIT 100;
