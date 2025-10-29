-- {"query": "3256.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2539}
WITH
usr_stats AS (
    SELECT
        u.Id AS user_id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS net_votes,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS gold_badges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS silver_badges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS bronze_badges,
        MAX(p.CreationDate) AS last_post_date
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),
recent_votes AS (
    SELECT
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Id = 2) AS up_votes_30d,
        COUNT(*) FILTER (WHERE vt.Id = 3) AS down_votes_30d,
        MAX(v.CreationDate) AS last_vote_date
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= DATE '2024-10-01' - INTERVAL '30 days'
    GROUP BY v.UserId
),
tag_stats AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS question_cnt,
        SUM(p.Score) AS total_score,
        AVG(p.ViewCount) AS avg_views,
        MAX(p.CreationDate) AS latest_question,
        STRING_AGG(DISTINCT u.DisplayName, ', ')
            FILTER (WHERE u.Id IS NOT NULL) AS contributors
    FROM Tags t
    JOIN Posts p
      ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
     AND p.PostTypeId = 1
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    GROUP BY t.TagName
),
usr_tag_score AS (
    SELECT
        us.user_id,
        t.TagName,
        COUNT(p.Id) AS usr_question_cnt,
        SUM(p.Score) AS usr_total_score,
        ROW_NUMBER() OVER (PARTITION BY us.user_id
                           ORDER BY SUM(p.Score) DESC NULLS LAST) AS tag_rank
    FROM usr_stats us
    JOIN Posts p
      ON p.OwnerUserId = us.user_id
     AND p.PostTypeId = 1
    JOIN LATERAL (
        SELECT UNNEST(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags)-2), '><')) AS tag
    ) pt ON TRUE
    JOIN Tags t ON t.TagName = pt.tag
    GROUP BY us.user_id, t.TagName
),
never_posted AS (
    SELECT u.Id AS user_id
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.Id IS NULL
)
SELECT
    us.user_id,
    us.DisplayName,
    us.Reputation,
    us.net_votes,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    COALESCE(rv.up_votes_30d, 0) AS up_votes_last30d,
    COALESCE(rv.down_votes_30d, 0) AS down_votes_last30d,
    us.last_post_date,
    CASE
        WHEN us.last_post_date IS NULL THEN 'Never Posted'
        WHEN us.last_post_date < DATE '2024-10-01' - INTERVAL '365 days' THEN 'Dormant'
        ELSE 'Active'
    END AS activity_status,
    STRING_AGG(CONCAT(uts.TagName, ':', uts.usr_total_score), '; ')
        FILTER (WHERE uts.tag_rank = 1) AS top_tag_score
FROM usr_stats us
LEFT JOIN recent_votes rv ON rv.UserId = us.user_id
LEFT JOIN usr_tag_score uts ON uts.user_id = us.user_id
WHERE (us.Reputation > 25000 OR us.gold_badges >= 5)
GROUP BY
    us.user_id, us.DisplayName, us.Reputation, us.net_votes,
    us.gold_badges, us.silver_badges, us.bronze_badges,
    rv.up_votes_30d, rv.down_votes_30d, us.last_post_date
UNION ALL
SELECT
    np.user_id,
    u.DisplayName,
    u.Reputation,
    0 AS net_votes,
    COUNT(b.Id) FILTER (WHERE b.Class = 1) AS gold_badges,
    COUNT(b.Id) FILTER (WHERE b.Class = 2) AS silver_badges,
    COUNT(b.Id) FILTER (WHERE b.Class = 3) AS bronze_badges,
    0 AS up_votes_last30d,
    0 AS down_votes_last30d,
    NULL AS last_post_date,
    'No Posts' AS activity_status,
    NULL AS top_tag_score
FROM never_posted np
JOIN Users u ON u.Id = np.user_id
LEFT JOIN Badges b ON b.UserId = u.Id
GROUP BY np.user_id, u.DisplayName, u.Reputation
ORDER BY Reputation DESC NULLS LAST
LIMIT 100;