-- {"query": "3871.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2376} 

/*  Benchmark‑heavy query illustrating CTEs, window functions, outer joins,
    correlated sub‑queries, set operators, string handling and NULL logic. */
WITH RecentQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                           ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1                                   -- only questions
      AND p.CreationDate > CURRENT_DATE - INTERVAL '30 days'
),
UserBadgeCounts AS (
    SELECT
        u.Id               AS UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(b.Id)                           AS TotalBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),
TagUsage AS (
    SELECT
        t.TagName,
        COUNT(p.Id)                     AS QuestionCount,
        SUM(p.Score)                    AS TotalScore,
        MAX(p.CreationDate)             AS LastUsed
    FROM Tags t
    JOIN Posts p
      ON p.PostTypeId = 1
     AND p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    GROUP BY t.TagName
),
PostVotes AS (
    SELECT
        p.Id                                            AS PostId,
        COALESCE(SUM(CASE
                        WHEN v.VoteTypeId = 2 THEN 1   -- upvote
                        WHEN v.VoteTypeId = 3 THEN -1  -- downvote
                        ELSE 0
                     END),0)                           AS NetScore,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 5)       AS FavoriteCount
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.Id
)

SELECT
    u.Id                                    AS UserId,
    COALESCE(u.DisplayName,'Anonymous')      AS DisplayName,
    u.Reputation,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TotalBadges,
    rq.Title,
    rq.CreationDate                         AS QuestionDate,
    pv.NetScore,
    pv.FavoriteCount,
    CASE WHEN rq.rn = 1 THEN 'MostRecent' ELSE 'Earlier' END AS RecencyFlag,
    (SELECT STRING_AGG(t, ';')
       FROM UNNEST(string_to_array(rq.Tags, '><')) AS t
       WHERE t <> '')                         AS TagList
FROM Users u
LEFT JOIN UserBadgeCounts ub
       ON ub.UserId = u.Id
LEFT JOIN RecentQuestions rq
       ON rq.OwnerUserId = u.Id AND rq.rn <= 3
LEFT JOIN PostVotes pv
       ON pv.PostId = rq.Id
FULL OUTER JOIN (
    SELECT TagName FROM TagUsage WHERE QuestionCount > 1000
) AS heavy_tags
       ON heavy_tags.TagName = ANY (string_to_array(rq.Tags, '><'))
WHERE u.CreationDate < CURRENT_DATE - INTERVAL '365 days'
   OR u.Reputation > 10000
ORDER BY u.Reputation DESC, ub.TotalBadges DESC
LIMIT 100

UNION ALL

SELECT
    NULL                                    AS UserId,
    '--- Tag Summary ---'                   AS DisplayName,
    NULL                                    AS Reputation,
    NULL                                    AS GoldBadges,
    NULL                                    AS SilverBadges,
    NULL                                    AS BronzeBadges,
    NULL                                    AS TotalBadges,
    tu.TagName                               AS Title,
    tu.LastUsed                              AS QuestionDate,
    tu.TotalScore                            AS NetScore,
    tu.QuestionCount                         AS FavoriteCount,
    NULL                                    AS RecencyFlag,
    NULL                                    AS TagList
FROM TagUsage tu
WHERE tu.QuestionCount > 5000
ORDER BY tu.QuestionCount DESC
LIMIT 20;
