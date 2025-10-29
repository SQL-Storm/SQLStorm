-- {"query": "3414.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2157} 

/*  Benchmark‑heavy query on the StackOverflow schema  */
WITH TagStats AS (
    SELECT
        t.TagName,
        date_trunc('month', p.CreationDate)          AS month,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)     AS question_cnt,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS avg_score,
        ROW_NUMBER() OVER (
            PARTITION BY date_trunc('month', p.CreationDate)
            ORDER BY COUNT(*) FILTER (WHERE p.PostTypeId = 1) DESC
        )                                            AS rn
    FROM Posts p
    CROSS JOIN LATERAL
        (SELECT trim(both '<>' FROM unnest(string_to_array(p.Tags,'><'))) AS tag) AS tgs
    JOIN Tags t ON t.TagName = tgs.tag
    WHERE p.PostTypeId = 1                -- only questions
      AND p.CreationDate >= '2023-01-01'::timestamp
    GROUP BY t.TagName, date_trunc('month', p.CreationDate)
),
TopTags AS (
    SELECT TagName, month, question_cnt, avg_score
    FROM TagStats
    WHERE rn <= 5
),
UserActivity AS (
    SELECT
        u.Id                                    AS user_id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS questions_asked,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS answers_given,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS upvotes_given,
        COUNT(b.Id) FILTER (WHERE b.Class = 1)      AS gold_badges,
        ROW_NUMBER() OVER (
            ORDER BY (COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) * 2
                     + COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)) DESC
        )                                            AS activity_rank
    FROM Users u
    LEFT JOIN Posts  p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes  v ON v.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
LatestCloseReason AS (
    SELECT
        ph.PostId,
        ph.Comment AS close_reason_id,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10               -- Close event
),
AggregatedPosts AS (
    SELECT
        p.Id                                   AS post_id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        COALESCE(lc.close_reason_id,'0')      AS close_reason_id,
        COALESCE(bc.badge_cnt,0)               AS badge_cnt,
        COALESCE(vu.up_votes,0) - COALESCE(vd.down_votes,0) AS vote_balance,
        ua.activity_rank
    FROM Posts p
    LEFT JOIN LatestCloseReason lc
           ON lc.PostId = p.Id AND lc.rn = 1
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS badge_cnt
        FROM Badges
        GROUP BY OwnerUserId
    ) bc ON bc.OwnerUserId = p.OwnerUserId
    LEFT JOIN (
        SELECT PostId,
               COUNT(*) FILTER (WHERE VoteTypeId = 2) AS up_votes,
               COUNT(*) FILTER (WHERE VoteTypeId = 3) AS down_votes
        FROM Votes
        GROUP BY PostId
    ) vu ON vu.PostId = p.Id
    LEFT JOIN (
        SELECT PostId,
               COUNT(*) FILTER (WHERE VoteTypeId = 3) AS down_votes
        FROM Votes
        GROUP BY PostId
    ) vd ON vd.PostId = p.Id
    LEFT JOIN UserActivity ua
           ON ua.user_id = p.OwnerUserId AND ua.activity_rank <= 100
    WHERE p.PostTypeId = 1                         -- questions only
      AND p.CreationDate >= '2023-01-01'::timestamp
      AND (p.Score IS NULL OR p.Score > 0)
)
SELECT *
FROM AggregatedPosts
WHERE badge_cnt > 5

UNION ALL

SELECT
    NULL                                    AS post_id,
    t.TagName || ' – ' || to_char(t.month,'YYYY-MM') AS title,
    t.question_cnt                         AS score,
    NULL                                    AS viewcount,
    t.month                                 AS creationdate,
    NULL                                    AS close_reason_id,
    NULL                                    AS badge_cnt,
    NULL                                    AS vote_balance,
    NULL                                    AS activity_rank
FROM TopTags t

ORDER BY creationdate DESC, score DESC
LIMIT 200;
