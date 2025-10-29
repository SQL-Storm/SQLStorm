WITH 
UserBadgeStats AS (
    SELECT 
        u.Id                              AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        COUNT(b.Id)                       AS TotalBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserQuestionScore AS (
    SELECT 
        p.OwnerUserId                AS UserId,
        ROUND(AVG(p.Score), 2)       AS AvgQuestionScore,
        COUNT(*)                     AS QuestionCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserLatestPost AS (
    SELECT 
        p.OwnerUserId                AS UserId,
        p.Id                         AS LatestPostId,
        p.Title,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId 
                           ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),
UserTagDiversity AS (
    SELECT 
        q.OwnerUserId                     AS UserId,
        COUNT(DISTINCT tag)                AS DistinctTagCount
    FROM Posts q
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(TRIM(BOTH '<>' FROM q.Tags), '><')) AS tag
    ) t
    WHERE q.PostTypeId = 1
      AND q.Tags IS NOT NULL
    GROUP BY q.OwnerUserId
),
Voters AS (
    SELECT DISTINCT v.UserId
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    UNION ALL
    SELECT DISTINCT c.UserId
    FROM Comments c
    WHERE c.UserId IS NOT NULL
),
EnrichedUsers AS (
    SELECT 
        ub.UserId,
        ub.DisplayName,
        ub.Reputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TotalBadges,
        COALESCE(uqs.AvgQuestionScore, 0)      AS AvgQuestionScore,
        COALESCE(uqs.QuestionCount, 0)         AS QuestionCount,
        COALESCE(utd.DistinctTagCount, 0)      AS DistinctTagCount,
        COALESCE(lp.Title, '(no posts)')       AS LatestPostTitle,
        CASE 
            WHEN u.LastAccessDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days') THEN TRUE
            ELSE FALSE
        END                                     AS IsRecentlyActive,
        (ub.Reputation * 0.4
         + ub.TotalBadges * 10
         + COALESCE(uqs.AvgQuestionScore,0) * 5
         + COALESCE(utd.DistinctTagCount,0) * 2) AS CompositeScore
    FROM UserBadgeStats ub
    LEFT JOIN UserQuestionScore uqs ON uqs.UserId = ub.UserId
    LEFT JOIN UserTagDiversity utd   ON utd.UserId = ub.UserId
    LEFT JOIN (
        SELECT UserId, Title
        FROM UserLatestPost
        WHERE rn = 1
    ) lp ON lp.UserId = ub.UserId
    JOIN Users u ON u.Id = ub.UserId
)
SELECT
    eu.UserId,
    eu.DisplayName,
    eu.Reputation,
    eu.GoldBadges,
    eu.SilverBadges,
    eu.BronzeBadges,
    eu.TotalBadges,
    eu.AvgQuestionScore,
    eu.QuestionCount,
    eu.DistinctTagCount,
    eu.LatestPostTitle,
    eu.IsRecentlyActive,
    eu.CompositeScore,
    CASE WHEN v.UserId IS NOT NULL THEN TRUE ELSE FALSE END AS HasVotedOrCommented
FROM EnrichedUsers eu
LEFT JOIN Voters v ON v.UserId = eu.UserId
WHERE eu.Reputation > 1000
ORDER BY eu.CompositeScore DESC
LIMIT 100;