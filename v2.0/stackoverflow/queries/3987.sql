-- {"query": "3987.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2087}
WITH 
RecentPosts AS (
    SELECT 
        p.Id               AS PostId,
        p.OwnerUserId      AS UserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId 
                           ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30' DAY
      AND p.PostTypeId IN (1,2)
),
UserBadgeStats AS (
    SELECT 
        u.Id                                   AS UserId,
        COUNT(b.Id)                            AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS Gold,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS Silver,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS Bronze,
        MAX(b.Date)                            AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),
TagUsage AS (
    SELECT 
        p.OwnerUserId                AS UserId,
        t.tag                        AS Tag,
        COUNT(*)                     AS TagCnt
    FROM Posts p
    CROSS JOIN LATERAL (
      SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2), '><')) AS tag
    ) t
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, t.tag
),
TopTagPerUser AS (
    SELECT 
        tu.UserId,
        tu.Tag,
        tu.TagCnt,
        ROW_NUMBER() OVER (PARTITION BY tu.UserId 
                           ORDER BY tu.TagCnt DESC, tu.Tag) AS rn
    FROM TagUsage tu
),
ActiveAnswerers AS (
    SELECT 
        u.Id                           AS UserId,
        CASE 
            WHEN EXISTS (SELECT 1 
                         FROM Posts a 
                         WHERE a.OwnerUserId = u.Id 
                           AND a.PostTypeId = 2
                           AND a.Score > 10) 
                 THEN 1 
            ELSE 0 
        END                           AS HasHighScoringAnswer
    FROM Users u
),
MainResults AS (
    SELECT 
        u.Id                                      AS UserId,
        COALESCE(u.DisplayName, '[deleted]')      AS DisplayName,
        u.Reputation,
        COALESCE(ubs.TotalBadges,0)                AS TotalBadges,
        COALESCE(ubs.Gold,0)                       AS GoldBadges,
        COALESCE(ubs.Silver,0)                     AS SilverBadges,
        COALESCE(ubs.Bronze,0)                     AS BronzeBadges,
        u.CreationDate,
        CASE WHEN aa.HasHighScoringAnswer = 1 
             THEN 'ActiveAnswerer' 
             ELSE 'Quiet' 
        END                                        AS ActivityFlag,
        tt.Tag                                    AS TopTag,
        tt.TagCnt                                 AS TopTagCount,
        rp.PostId                                 AS RecentPostId,
        rp.Score                                  AS RecentPostScore,
        rp.CreationDate                           AS RecentPostDate,
        ubs.LastBadgeDate                          AS LastBadgeDate
    FROM Users u
    LEFT JOIN UserBadgeStats ubs      ON ubs.UserId = u.Id
    LEFT JOIN (SELECT UserId, Tag, TagCnt
               FROM TopTagPerUser
               WHERE rn = 1) tt      ON tt.UserId = u.Id
    LEFT JOIN RecentPosts rp         ON rp.UserId = u.Id AND rp.rn = 1
    LEFT JOIN ActiveAnswerers aa     ON aa.UserId = u.Id
    WHERE u.Reputation > 1000
      AND (ubs.TotalBadges IS NULL OR ubs.TotalBadges >= 5)
      AND (rp.Score IS NULL OR rp.Score >= 0)
)
SELECT *
FROM (
    SELECT UserId, DisplayName, Reputation, TotalBadges, GoldBadges, SilverBadges, BronzeBadges,
           CreationDate, ActivityFlag, TopTag, TopTagCount, RecentPostId, RecentPostScore, RecentPostDate, LastBadgeDate
    FROM MainResults
    ORDER BY Reputation DESC, TotalBadges DESC
    LIMIT 100
) AS paged

UNION ALL

SELECT 
    NULL AS UserId, '[sentinel]' AS DisplayName, NULL AS Reputation, NULL AS TotalBadges, NULL AS GoldBadges, NULL AS SilverBadges, NULL AS BronzeBadges,
    NULL AS CreationDate, NULL AS ActivityFlag, NULL AS TopTag, NULL AS TopTagCount, NULL AS RecentPostId, NULL AS RecentPostScore, NULL AS RecentPostDate, NULL AS LastBadgeDate
FROM (SELECT 1) AS dummy

EXCEPT

SELECT 
    UserId, NULL AS DisplayName, NULL AS Reputation, NULL AS TotalBadges, NULL AS GoldBadges, NULL AS SilverBadges, NULL AS BronzeBadges,
    NULL AS CreationDate, NULL AS ActivityFlag, NULL AS TopTag, NULL AS TopTagCount, NULL AS RecentPostId, NULL AS RecentPostScore, NULL AS RecentPostDate, NULL AS LastBadgeDate
FROM (
    SELECT DISTINCT OwnerUserId AS UserId
    FROM Posts
    WHERE PostTypeId = 1
      AND Score < 0
) AS NegQs;