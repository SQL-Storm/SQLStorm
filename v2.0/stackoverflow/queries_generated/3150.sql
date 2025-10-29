-- {"query": "3150.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2641} 

WITH RecentPosts AS (
    SELECT 
        p.OwnerUserId,
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 
            ELSE 0 
        END AS HasAccepted,
        COALESCE(p.Tags, '') AS Tags
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
),
UserAgg AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(u.Reputation, 0) AS Reputation,
        COUNT(rp.PostId) FILTER (WHERE rp.PostTypeId = 1) AS QuestionCount30d,
        COUNT(rp.PostId) FILTER (WHERE rp.PostTypeId = 2) AS AnswerCount30d,
        SUM(rp.Score) AS TotalScore30d,
        AVG(rp.Score) FILTER (WHERE rp.PostTypeId = 2) AS AvgAnswerScore,
        SUM(rp.HasAccepted) FILTER (WHERE rp.PostTypeId = 1) AS AcceptedAnswerCount,
        MAX(rp.CreationDate) AS LastPostDate,
        COALESCE(u.Location, '[Unknown]') AS Location,
        COALESCE(u.WebsiteUrl, '') AS Website
    FROM Users u
    LEFT JOIN RecentPosts rp ON u.Id = rp.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, u.WebsiteUrl
),
BadgeAgg AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadgeCount,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadgeCount,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadgeCount,
        STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.Class = 1) AS GoldBadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
TagAgg AS (
    SELECT 
        u.Id AS UserId,
        TRIM(t) AS TagName,
        COUNT(*) AS TagUseCount
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id 
                 AND p.PostTypeId = 1 
                 AND p.Tags IS NOT NULL
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t
    ) AS lt
    GROUP BY u.Id, TagName
),
TopTagPerUser AS (
    SELECT 
        ta.UserId,
        ta.TagName,
        ta.TagUseCount,
        ROW_NUMBER() OVER (PARTITION BY ta.UserId ORDER BY ta.TagUseCount DESC) AS rn
    FROM TagAgg ta
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.QuestionCount30d,
    ua.AnswerCount30d,
    ua.TotalScore30d,
    ROUND(ua.AvgAnswerScore::numeric, 2)        AS AvgAnswerScore,
    ua.AcceptedAnswerCount,
    ua.LastPostDate,
    COALESCE(ba.GoldBadgeCount, 0)              AS GoldBadgeCount,
    COALESCE(ba.SilverBadgeCount, 0)            AS SilverBadgeCount,
    COALESCE(ba.BronzeBadgeCount, 0)            AS BronzeBadgeCount,
    COALESCE(ba.GoldBadgeNames, '')             AS GoldBadgeNames,
    tt.TagName                                   AS TopTag,
    tt.TagUseCount                               AS TopTagUseCount,
    CASE 
        WHEN ua.AnswerCount30d = 0 THEN NULL 
        ELSE ua.AcceptedAnswerCount::float / ua.AnswerCount30d 
    END                                          AS AcceptanceRate,
    CASE 
        WHEN ua.Reputation >= 20000 THEN 'Elite'
        WHEN ua.Reputation >= 10000 THEN 'Trusted'
        WHEN ua.Reputation >= 1000  THEN 'Contributor'
        ELSE 'Newbie'
    END                                          AS ReputationTier
FROM UserAgg ua
LEFT JOIN BadgeAgg ba      ON ua.UserId = ba.UserId
LEFT JOIN TopTagPerUser tt ON ua.UserId = tt.UserId AND tt.rn = 1
WHERE ua.Reputation IS NOT NULL
ORDER BY ua.Reputation DESC
LIMIT 100

UNION ALL

SELECT 
    NULL                                           AS UserId,
    'TOTAL'                                        AS DisplayName,
    SUM(ua.Reputation)                             AS Reputation,
    SUM(ua.QuestionCount30d)                       AS QuestionCount30d,
    SUM(ua.AnswerCount30d)                         AS AnswerCount30d,
    SUM(ua.TotalScore30d)                          AS TotalScore30d,
    ROUND(AVG(ua.AvgAnswerScore)::numeric, 2)      AS AvgAnswerScore,
    SUM(ua.AcceptedAnswerCount)                    AS AcceptedAnswerCount,
    NULL                                           AS LastPostDate,
    SUM(COALESCE(ba.GoldBadgeCount, 0))            AS GoldBadgeCount,
    SUM(COALESCE(ba.SilverBadgeCount, 0))          AS SilverBadgeCount,
    SUM(COALESCE(ba.BronzeBadgeCount, 0))          AS BronzeBadgeCount,
    NULL                                           AS GoldBadgeNames,
    NULL                                           AS TopTag,
    NULL                                           AS TopTagUseCount,
    NULL                                           AS AcceptanceRate,
    NULL                                           AS ReputationTier
FROM UserAgg ua
LEFT JOIN BadgeAgg ba ON ua.UserId = ba.UserId
HAVING COUNT(*) > 1;
