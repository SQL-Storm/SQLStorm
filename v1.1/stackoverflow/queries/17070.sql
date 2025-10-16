WITH UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        DENSE_RANK() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY u.Reputation DESC) AS location_rank,
        COUNT(DISTINCT p.Id) AS post_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_count,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS avg_post_score,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS accepted_answers,
        COALESCE(
            STRING_AGG(badge_initial, '|' ORDER BY b.Class, b.Name),
            ''
        ) AS badge_initials
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365 days'
    LEFT JOIN (
        SELECT DISTINCT UserId, Class, Name, SUBSTRING(UPPER(COALESCE(Name, '')), 1, 3) AS badge_initial
        FROM Badges
        WHERE TagBased = 'true'
    ) b ON u.Id = b.UserId
    WHERE u.CreationDate < CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days'
        AND (u.Reputation > 100 OR u.Reputation IS NULL)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
QuestionStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.Tags,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.OwnerUserId,
        COUNT(DISTINCT a.Id) AS total_answers,
        MAX(a.Score) AS best_answer_score,
        MIN(a.CreationDate) AS first_answer_time,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.Score) AS median_answer_score,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id AND c.Score > 5) AS high_score_comments,
        EXISTS (
            SELECT 1 FROM PostHistory ph 
            WHERE ph.PostId = q.Id 
                AND ph.PostHistoryTypeId IN (10, 12)
                AND ph.Comment LIKE '%duplicate%'
        ) AS has_duplicate_history
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1 
        AND q.CreationDate BETWEEN CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '730 days' AND CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
        AND LENGTH(COALESCE(q.Title, '')) > 20
    GROUP BY q.Id, q.Title, q.Tags, q.Score, q.ViewCount, q.OwnerUserId
    HAVING COUNT(DISTINCT a.Id) > 0 OR q.Score > 10
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS tag_usage_count,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) AS prev_tag_count,
        LEAD(t.Count, 1) OVER (ORDER BY t.Count DESC) AS next_tag_count,
        CASE 
            WHEN t.Count > COALESCE(LAG(t.Count, 1) OVER (ORDER BY t.Count DESC), 0) * 1.5 THEN 'Growing'
            WHEN t.Count < COALESCE(LAG(t.Count, 1) OVER (ORDER BY t.Count DESC), 0) * 0.7 THEN 'Declining'
            ELSE 'Stable'
        END AS trend,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS popularity_rank
    FROM Tags t
    WHERE t.Count > 100
        AND t.WikiPostId IS NOT NULL
)
SELECT 
    um.DisplayName,
    um.Location,
    um.Reputation,
    um.location_rank,
    um.question_count + um.answer_count AS total_contributions,
    ROUND(CAST(um.accepted_answers AS NUMERIC) / NULLIF(um.answer_count, 0) * 100, 2) AS accept_rate,
    um.avg_post_score,
    COALESCE(NULLIF(um.badge_initials, ''), 'NONE') AS badges,
    qs.Title AS top_question,
    REPLACE(REPLACE(qs.Tags, '<', ''), '>', ', ') AS question_tags,
    qs.QuestionScore,
    qs.ViewCount,
    qs.total_answers,
    qs.best_answer_score,
    EXTRACT(EPOCH FROM (qs.first_answer_time - p.CreationDate)) / 3600 AS hours_to_first_answer,
    qs.median_answer_score,
    qs.high_score_comments,
    ta.TagName AS primary_tag,
    ta.trend AS tag_trend,
    ta.popularity_rank AS tag_rank,
    CASE 
        WHEN um.Reputation > 10000 AND um.location_rank = 1 THEN 'Elite Local Expert'
        WHEN um.accepted_answers > 50 THEN 'Prolific Solver'
        WHEN qs.ViewCount > 100000 THEN 'Viral Question Author'
        WHEN um.avg_post_score > 20 THEN 'Quality Contributor'
        WHEN qs.has_duplicate_history THEN 'Duplicate Magnet'
        ELSE 'Regular User'
    END AS user_category,
    (
        SELECT COUNT(DISTINCT v.UserId)
        FROM Votes v
        WHERE v.PostId IN (
            SELECT p2.Id 
            FROM Posts p2 
            WHERE p2.OwnerUserId = um.Id
        )
        AND v.VoteTypeId = 2
        AND v.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
    ) AS recent_upvoters,
    COALESCE(
        (
            SELECT STRING_AGG(CAST(pl.LinkTypeId AS VARCHAR), ',' ORDER BY CAST(pl.LinkTypeId AS VARCHAR))
            FROM PostLinks pl
            WHERE pl.PostId = qs.QuestionId OR pl.RelatedPostId = qs.QuestionId
        ),
        'No Links'
    ) AS link_types
FROM UserMetrics um
INNER JOIN QuestionStats qs ON um.Id = qs.OwnerUserId
INNER JOIN Posts p ON qs.QuestionId = p.Id
LEFT JOIN LATERAL (
    SELECT ta2.*
    FROM TagAnalysis ta2
    WHERE qs.Tags LIKE '%' || '<' || ta2.TagName || '>' || '%'
    ORDER BY ta2.popularity_rank
    LIMIT 1
) ta ON TRUE
WHERE um.location_rank <= 5
    AND (qs.QuestionScore > 5 OR qs.ViewCount > 1000)
    AND (qs.total_answers >= 3 OR qs.best_answer_score > 10)
    AND NOT (um.DisplayName IS NULL AND qs.Title IS NULL)
GROUP BY
    um.DisplayName,
    um.Location,
    um.Reputation,
    um.location_rank,
    um.question_count,
    um.answer_count,
    um.accepted_answers,
    um.avg_post_score,
    um.badge_initials,
    qs.Title,
    qs.Tags,
    qs.QuestionScore,
    qs.ViewCount,
    qs.total_answers,
    qs.best_answer_score,
    qs.first_answer_time,
    qs.median_answer_score,
    qs.high_score_comments,
    ta.TagName,
    ta.trend,
    ta.popularity_rank,
    qs.has_duplicate_history,
    p.CreationDate,
    um.Id,
    qs.OwnerUserId,
    qs.QuestionId
ORDER BY 
    um.Reputation DESC NULLS LAST,
    qs.ViewCount DESC NULLS LAST,
    qs.QuestionScore DESC NULLS LAST
LIMIT 100;