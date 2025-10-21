-- {"query": "39015.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2478} 

WITH UserBadgeStats AS (
    SELECT
        u.Id       AS user_id,
        u.DisplayName,
        COUNT(b.Id)                                           AS total_badges,
        COUNT(b.Id) FILTER (WHERE b.Class = 1)                AS gold_badges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2)                AS silver_badges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3)                AS bronze_badges,
        MAX(b.Date)                                          AS last_badge_date
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
PostTagCounts AS (
    SELECT
        p.Id                                                   AS post_id,
        COUNT(t.Id)                                           AS tag_count,
        STRING_AGG(t.TagName, ',' ORDER BY t.TagName)         AS tag_list
    FROM Posts p
    JOIN unnest(
           string_to_array(
             substring(p.Tags, 2, length(p.Tags) - 2),
             '><'
           )
         ) AS tn(TagName) ON TRUE
    JOIN Tags t ON t.TagName = tn.TagName
    GROUP BY p.Id
),
TopActiveUsers AS (
    SELECT
        ub.user_id,
        ub.DisplayName,
        ub.total_badges,
        ub.gold_badges,
        ub.silver_badges,
        COUNT(DISTINCT p.Id)                                 AS posts_count,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)     AS upvotes_received,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)     AS downvotes_received,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS rn
    FROM UserBadgeStats ub
    JOIN Posts p ON p.OwnerUserId = ub.user_id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY ub.user_id, ub.DisplayName, ub.total_badges, ub.gold_badges, ub.silver_badges
    HAVING COUNT(DISTINCT p.Id) > 10
),
RecentHistory AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        COALESCE(
          CASE
            WHEN ph.PostHistoryTypeId IN (10,11,12,13,14,15,19,20,35)
              THEN (ph.Text::json ->> 'action')
            ELSE ph.Comment
          END,
          ph.Comment
        )                                                    AS action_info,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
)
SELECT
    tu.rn                     AS user_rank,
    tu.DisplayName            AS user_name,
    tu.posts_count,
    tu.upvotes_received,
    tu.downvotes_received,
    tu.gold_badges,
    tu.silver_badges,
    ptc.tag_count,
    ptc.tag_list,
    rh.PostHistoryTypeId      AS last_history_type,
    rh.CreationDate           AS last_history_date,
    rh.action_info            AS last_history_info
FROM TopActiveUsers tu
JOIN Posts p2 ON p2.OwnerUserId = tu.user_id
LEFT JOIN PostTagCounts ptc ON ptc.post_id = p2.Id
LEFT JOIN RecentHistory rh ON rh.PostId = p2.Id AND rh.rn = 1
ORDER BY tu.rn, p2.Id
LIMIT 50;
