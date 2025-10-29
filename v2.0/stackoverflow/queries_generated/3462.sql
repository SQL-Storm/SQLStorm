-- {"query": "3462.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2345} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, '[unknown]')               AS Location,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)     AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)     AS AnswerCount,
        SUM(p.Score)                                   AS TotalScore,
        MAX(p.CreationDate)                            AS LastPostDate,
        MAX(p.LastActivityDate)                        AS LastActivity,
        COUNT(DISTINCT 
            CASE 
                WHEN p.Tags IS NOT NULL 
                THEN UNNEST(string_to_array(p.Tags, '><')) 
            END
        )                                              AS DistinctTagCount
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
BadgeCounts AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*)                                     AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
TopTagUsage AS (
    SELECT 
        u.Id                                 AS UserId,
        t.TagName,
        COUNT(*)                             AS TagUseCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS rn
    FROM Users u
    JOIN Posts p 
        ON p.OwnerUserId = u.Id 
        AND p.PostTypeId = 1 
        AND p.Tags IS NOT NULL
    CROSS JOIN LATERAL UNNEST(string_to_array(p.Tags, '><')) AS tag(TagName)
    JOIN Tags t 
        ON t.TagName = tag.TagName
    GROUP BY u.Id, t.TagName
),
RecentVotes AS (
    SELECT 
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod')   AS UpVotes,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVotes,
        MAX(v.CreationDate)                         AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.UserId
),
Combined AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.QuestionCount,
        us.AnswerCount,
        us.TotalScore,
        us.LastActivity,
        COALESCE(bc.GoldBadges,0)   AS GoldBadges,
        COALESCE(bc.SilverBadges,0) AS SilverBadges,
        COALESCE(bc.BronzeBadges,0) AS BronzeBadges,
        COALESCE(rv.UpVotes,0)      AS RecentUpVotes,
        COALESCE(rv.DownVotes,0)    AS RecentDownVotes,
        CASE
            WHEN us.Reputation >= 20000 THEN 'Legendary'
            WHEN us.Reputation >= 10000 THEN 'Expert'
            WHEN us.Reputation >= 5000  THEN 'Seasoned'
            ELSE 'Novice'
        END                         AS ReputationTier,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC) AS RepRank
    FROM UserStats us
    LEFT JOIN BadgeCounts bc   ON bc.UserId = us.Id
    LEFT JOIN RecentVotes rv   ON rv.UserId = us.Id
)
SELECT 
    c.Id,
    c.DisplayName,
    c.Reputation,
    c.QuestionCount,
    c.AnswerCount,
    c.TotalScore,
    c.RepRank,
    c.ReputationTier,
    c.GoldBadges,
    c.SilverBadges,
    c.BronzeBadges,
    c.RecentUpVotes,
    c.RecentDownVotes,
    COALESCE(tu.TagName, 'None')   AS TopTag,
    COALESCE(tu.TagUseCount,0)    AS TopTagCount
FROM Combined c
LEFT JOIN (
    SELECT UserId, TagName, TagUseCount
    FROM TopTagUsage
    WHERE rn = 1
) tu ON tu.UserId = c.Id
WHERE c.RepRank <= 1000
ORDER BY c.RepRank

UNION ALL

SELECT 
    NULL AS Id,
    '---' AS DisplayName,
    NULL AS Reputation,
    NULL AS QuestionCount,
    NULL AS AnswerCount,
    NULL AS TotalScore,
    NULL AS RepRank,
    NULL AS ReputationTier,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    NULL AS RecentUpVotes,
    NULL AS RecentDownVotes,
    NULL AS TopTag,
    NULL AS TopTagCount
WHERE NOT EXISTS (SELECT 1 FROM Combined WHERE RepRank <= 1000);
