-- {"query": "3393.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1783} 

WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(bc.Gold,   0) AS GoldBadges,
        COALESCE(bc.Silver, 0) AS SilverBadges,
        COALESCE(bc.Bronze, 0) AS BronzeBadges,
        COALESCE(pc.PostCnt,   0) AS PostCount,
        COALESCE(pc.AnsCnt,   0) AS AnswerCount,
        (SELECT MAX(p.CreationDate)
         FROM Posts p
         WHERE p.OwnerUserId = u.Id) AS LastPostDate
    FROM Users u
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS Gold,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS Silver,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS Bronze
        FROM Badges
        GROUP BY UserId
    ) bc ON bc.UserId = u.Id
    LEFT JOIN (
        SELECT
            OwnerUserId,
            COUNT(*) FILTER (WHERE PostTypeId = 1) AS PostCnt,
            COUNT(*) FILTER (WHERE PostTypeId = 2) AS AnsCnt
        FROM Posts
        GROUP BY OwnerUserId
    ) pc ON pc.OwnerUserId = u.Id
),

RankedUsers AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.PostCount,
        us.AnswerCount,
        us.LastPostDate,
        COALESCE(avg_s.avg_score, 0)               AS AvgPostScore,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, avg_s.avg_score DESC) AS ReputationScoreRank,
        CASE
            WHEN us.LastAccessDate > CURRENT_TIMESTAMP - INTERVAL '30 days' THEN 'Active'
            ELSE 'Inactive'
        END                                        AS RecentActivityFlag,
        COALESCE(tg.TopTagsCSV, '')                AS TopTagsCSV
    FROM UserStats us
    LEFT JOIN LATERAL (
        SELECT AVG(p.Score)::NUMERIC(10,2) AS avg_score
        FROM Posts p
        WHERE p.OwnerUserId = us.Id
    ) avg_s ON TRUE
    LEFT JOIN LATERAL (
        SELECT STRING_AGG(t.TagName, ',') AS TopTagsCSV
        FROM (
            SELECT UNNEST(STRING_TO_ARRAY(p.Tags, '><')) AS raw_tag
            FROM Posts p
            WHERE p.OwnerUserId = us.Id
              AND p.PostTypeId = 1
            ORDER BY p.Score DESC
            LIMIT 5
        ) pt
        JOIN Tags t
          ON t.TagName = TRIM(BOTH '<>' FROM pt.raw_tag)
    ) tg ON TRUE
)

SELECT
    Id,
    DisplayName,
    Reputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    PostCount,
    AnswerCount,
    LastPostDate,
    AvgPostScore,
    ReputationScoreRank,
    RecentActivityFlag,
    TopTagsCSV
FROM RankedUsers
WHERE ReputationScoreRank <= 100

UNION ALL

SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    0        AS GoldBadges,
    0        AS SilverBadges,
    0        AS BronzeBadges,
    0        AS PostCount,
    0        AS AnswerCount,
    NULL     AS LastPostDate,
    NULL     AS AvgPostScore,
    NULL     AS ReputationScoreRank,
    'NoActivity' AS RecentActivityFlag,
    NULL     AS TopTagsCSV
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)

ORDER BY Reputation DESC NULLS LAST
LIMIT 200;
