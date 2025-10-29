-- {"query": "3873.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1913} 

WITH
    /* 1️⃣ Aggregate basic user/post statistics */
    user_stats AS (
        SELECT
            u.Id                              AS user_id,
            u.DisplayName                     AS display_name,
            u.Reputation                      AS reputation,
            COUNT(p.Id)                       AS total_posts,
            AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS avg_score,
            MAX(p.CreationDate)               AS last_post_date,
            /* most recent title – uses a correlated sub‑query to avoid duplication */
            (SELECT p2.Title
             FROM Posts p2
             WHERE p2.OwnerUserId = u.Id
               AND p2.CreationDate = MAX(p.CreationDate) OVER (PARTITION BY u.Id)
             ORDER BY p2.Id DESC
             LIMIT 1)                         AS recent_title
        FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),

    /* 2️⃣ Count badges by class (gold / silver / bronze) */
    badge_counts AS (
        SELECT
            b.UserId,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze
        FROM Badges b
        GROUP BY b.UserId
    ),

    /* 3️⃣ Build a comma‑separated list of distinct tags a user has ever used */
    user_tags AS (
        SELECT
            p.OwnerUserId                                              AS user_id,
            STRING_AGG(DISTINCT t.TagName, ', ') FILTER (WHERE t.TagName IS NOT NULL) AS tags
        FROM Posts p
        /* explode the <tag1><tag2>… string into rows */
        CROSS JOIN LATERAL (
            SELECT trim(both '<>' FROM unnest(string_to_array(p.Tags, '><'))) AS tag
        ) AS exploded(tag)
        LEFT JOIN Tags t ON t.TagName = exploded.tag
        WHERE p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId
    ),

    /* 4️⃣ Latest close‑reason (if any) per user – uses window function + outer join */
    recent_close AS (
        SELECT
            ph.UserId                              AS user_id,
            ph.Comment::int                        AS close_reason_id,
            ct.Name                                AS close_reason_name,
            ROW_NUMBER() OVER (PARTITION BY ph.UserId ORDER BY ph.CreationDate DESC) AS rn
        FROM PostHistory ph
        LEFT JOIN CloseReasonTypes ct ON ct.Id = ph.Comment::int
        WHERE ph.PostHistoryTypeId = 10               -- “Post Closed”
    ),

    /* 5️⃣ Top‑voted posts (union of up‑votes and favorites) for ranking */
    top_votes AS (
        SELECT
            v.PostId,
            v.VoteTypeId,
            v.CreationDate,
            p.OwnerUserId
        FROM Votes v
        JOIN Posts p ON p.Id = v.PostId
        WHERE v.VoteTypeId IN (2, 5)                 -- UpMod or Favorite
    ),
    top_post_per_user AS (
        SELECT
            OwnerUserId AS user_id,
            MAX(CreationDate) AS last_vote_date
        FROM top_votes
        GROUP BY OwnerUserId
    )

SELECT
    us.user_id,
    us.display_name,
    us.reputation,
    us.total_posts,
    ROUND(us.avg_score, 2)                              AS avg_score,
    COALESCE(bc.gold,   0)                              AS gold_badges,
    COALESCE(bc.silver, 0)                              AS silver_badges,
    COALESCE(bc.bronze, 0)                              AS bronze_badges,
    us.recent_title,
    ut.tags                                            AS tag_list,
    COALESCE(rc.close_reason_name, 'None')             AS last_close_reason,
    RANK() OVER (ORDER BY us.reputation DESC)          AS reputation_rank,
    tp.last_vote_date                                  AS last_vote_date
FROM user_stats us
LEFT JOIN badge_counts bc      ON bc.UserId   = us.user_id
LEFT JOIN user_tags ut         ON ut.user_id = us.user_id
LEFT JOIN recent_close rc      ON rc.user_id = us.user_id AND rc.rn = 1
LEFT JOIN top_post_per_user tp ON tp.user_id = us.user_id
WHERE us.reputation > 10000
ORDER BY reputation_rank
LIMIT 100
UNION ALL
SELECT
    NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL
ORDER BY reputation_rank;
