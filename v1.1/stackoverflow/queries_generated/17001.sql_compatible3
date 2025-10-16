WITH user_activity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS post_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_count,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score END) AS avg_post_score,
        MAX(p.Score) AS max_post_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS median_score
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
badge_rankings AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS gold_badges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS silver_badges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS bronze_badges,
        STRING_AGG(CASE WHEN Class = 1 THEN Name END, ', ') AS gold_badge_names,
        DENSE_RANK() OVER (ORDER BY COUNT(CASE WHEN Class = 1 THEN 1 END) DESC) AS gold_rank,
        CAST(NULL AS INTEGER) AS recent_badge_rank
    FROM Badges
    GROUP BY UserId
),
badge_recent AS (
    SELECT
        UserId,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY Date DESC) AS recent_badge_rank,
        Class,
        Name,
        Date
    FROM Badges
),
tag_expertise AS (
    SELECT 
        p.OwnerUserId,
        UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')) AS tag,
        COUNT(*) AS tag_posts,
        SUM(p.Score) AS tag_score,
        AVG(CASE WHEN p.ViewCount > 0 THEN LOG(p.ViewCount + 1) END) AS log_avg_views
    FROM Posts p
    WHERE p.Tags IS NOT NULL 
        AND p.OwnerUserId IS NOT NULL
        AND p.PostTypeId = 1
    GROUP BY p.OwnerUserId, tag
),
top_tag_experts AS (
    SELECT 
        te.OwnerUserId,
        te.tag,
        te.tag_posts,
        te.tag_score,
        t.Count AS global_tag_count,
        RANK() OVER (PARTITION BY te.tag ORDER BY te.tag_score DESC NULLS LAST) AS tag_rank,
        (te.tag_score * 1.0) / NULLIF(t.Count, 0) AS relative_expertise
    FROM tag_expertise te
    LEFT JOIN Tags t ON te.tag = t.TagName
    WHERE te.tag_posts >= 5
),
edit_patterns AS (
    SELECT 
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS edited_posts,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 END) AS edit_count,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (7,8,9) THEN 1 END) AS rollback_count,
        AVG(LENGTH(COALESCE(ph.Text, ''))) AS avg_edit_length,
        EXTRACT(DOW FROM ph.CreationDate) AS edit_day_of_week,
        COUNT(*) FILTER (WHERE CAST(ph.CreationDate AS time) BETWEEN TIME '00:00:00' AND TIME '06:00:00') AS night_edits
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId, EXTRACT(DOW FROM ph.CreationDate)
),
complex_post_metrics AS (
    SELECT 
        q.Id AS question_id,
        q.Title,
        q.OwnerUserId AS asker_id,
        a.Id AS answer_id,
        a.OwnerUserId AS answerer_id,
        q.Score AS q_score,
        a.Score AS a_score,
        CASE 
            WHEN q.AcceptedAnswerId = a.Id THEN 'accepted'
            WHEN a.Score > COALESCE((
                SELECT MAX(a2.Score) 
                FROM Posts a2 
                WHERE a2.ParentId = q.Id 
                    AND a2.Id != a.Id
            ), -999) THEN 'highest_scored'
            ELSE 'regular'
        END AS answer_status,
        COALESCE(q.ViewCount, 0) / NULLIF(EXTRACT(DAY FROM (TIMESTAMP '2024-10-01 12:34:56' - q.CreationDate)), 0) AS views_per_day,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id AND c.Score > 0) AS positive_comments,
        EXISTS(
            SELECT 1 
            FROM PostHistory ph 
            WHERE ph.PostId = a.Id 
                AND ph.PostHistoryTypeId = 10
        ) AS was_closed,
        LAG(a.Score, 1) OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate) AS prev_answer_score,
        FIRST_VALUE(a.CreationDate) OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate) AS first_answer_time
    FROM Posts q
    INNER JOIN Posts a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1 
        AND a.PostTypeId = 2
        AND q.Score >= 0
        AND q.AnswerCount > 0
),
main_rows AS (
    SELECT 
        ua.DisplayName,
        ua.Reputation,
        COALESCE(ua.question_count, 0) + COALESCE(ua.answer_count, 0) AS total_posts,
        ROUND(CAST(ua.avg_post_score AS numeric), 2) AS avg_score,
        COALESCE(br.gold_badges, 0) || '/' || COALESCE(br.silver_badges, 0) || '/' || COALESCE(br.bronze_badges, 0) AS badge_summary,
        SUBSTRING(COALESCE(br.gold_badge_names, 'None') FROM 1 FOR 50) AS top_gold_badges,
        (
            SELECT STRING_AGG(tag || ':' || CAST(tag_score AS text), ', ' ORDER BY tag_score DESC)
            FROM (
                SELECT tag, tag_score 
                FROM top_tag_experts tte 
                WHERE tte.OwnerUserId = ua.Id 
                    AND tte.tag_rank <= 10
                ORDER BY tag_score DESC
                LIMIT 3
            ) top_tags
        ) AS top_3_tags,
        COALESCE(
            (
                SELECT AVG(cpm.a_score)
                FROM complex_post_metrics cpm
                WHERE cpm.answerer_id = ua.Id
                    AND cpm.answer_status IN ('accepted', 'highest_scored')
                    AND cpm.views_per_day > 10
            ), 0
        ) AS avg_quality_answer_score,
        (
            SELECT COUNT(DISTINCT v.PostId)
            FROM Votes v
            INNER JOIN Posts p ON v.PostId = p.Id
            WHERE v.UserId = ua.Id
                AND v.VoteTypeId = 2
                AND p.OwnerUserId != ua.Id
                AND p.Score < 0
        ) AS upvoted_negative_posts,
        CASE 
            WHEN ua.Reputation > 50000 THEN 'Elite'
            WHEN ua.Reputation > 10000 THEN 'Expert'
            WHEN ua.Reputation > 5000 THEN 'Trusted'
            WHEN ua.Reputation > 2000 THEN 'Established'
            ELSE 'Active'
        END AS user_tier,
        COALESCE(
            (
                SELECT MAX(ep.edit_count)
                FROM edit_patterns ep
                WHERE ep.UserId = ua.Id
                    AND ep.edit_day_of_week IN (0, 6)
            ), 0
        ) AS max_weekend_edits,
        CAST(
            GREATEST(
                0,
                EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - (ua.Reputation * INTERVAL '1 minute'))) / 86400
            ) AS int
        ) AS pseudo_age_days
    FROM user_activity ua
    LEFT JOIN badge_rankings br ON ua.Id = br.UserId
    WHERE ua.post_count > 10
        AND (COALESCE(br.gold_badges,0) > 0 OR ua.max_post_score > 100)
        AND ua.DisplayName IS NOT NULL
        AND LENGTH(ua.DisplayName) > 3
        AND NOT EXISTS (
            SELECT 1
            FROM Posts p
            WHERE p.OwnerUserId = ua.Id
                AND p.ClosedDate IS NOT NULL
                AND p.Score < -5
        )
),
system_average AS (
    SELECT 
        'SYSTEM_AVERAGE' AS DisplayName,
        CAST(AVG(Reputation) AS int) AS Reputation,
        CAST(AVG(question_count + answer_count) AS int) AS total_posts,
        CAST(AVG(avg_post_score) AS numeric(10,2)) AS avg_score,
        CAST(NULL AS VARCHAR) AS badge_summary,
        CAST(NULL AS VARCHAR) AS top_gold_badges,
        CAST(NULL AS VARCHAR) AS top_3_tags,
        CAST(NULL AS numeric) AS avg_quality_answer_score,
        CAST(NULL AS int) AS upvoted_negative_posts,
        'AGGREGATE' AS user_tier,
        CAST(NULL AS int) AS max_weekend_edits,
        CAST(NULL AS int) AS pseudo_age_days
    FROM user_activity
    WHERE question_count + answer_count > 10
)
SELECT *
FROM (
    SELECT
        m.DisplayName,
        m.Reputation,
        m.total_posts,
        m.avg_score,
        m.badge_summary,
        m.top_gold_badges,
        m.top_3_tags,
        m.avg_quality_answer_score,
        m.upvoted_negative_posts,
        m.user_tier,
        m.max_weekend_edits,
        m.pseudo_age_days,
        CASE WHEN m.DisplayName = 'SYSTEM_AVERAGE' THEN 1 ELSE 0 END AS is_system
    FROM main_rows m
    UNION ALL
    SELECT
        s.DisplayName,
        s.Reputation,
        s.total_posts,
        s.avg_score,
        s.badge_summary,
        s.top_gold_badges,
        s.top_3_tags,
        s.avg_quality_answer_score,
        s.upvoted_negative_posts,
        s.user_tier,
        s.max_weekend_edits,
        s.pseudo_age_days,
        CASE WHEN s.DisplayName = 'SYSTEM_AVERAGE' THEN 1 ELSE 0 END AS is_system
    FROM system_average s
) combined
ORDER BY is_system, Reputation DESC, total_posts DESC
LIMIT 100;