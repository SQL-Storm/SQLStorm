-- {"query": "3136.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1376}
WITH
    UserBadgeAgg AS (
        SELECT 
            u.Id                                    AS UserId,
            u.DisplayName,
            u.Reputation,
            COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
            COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
            COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
            COUNT(*)                                 AS TotalBadges
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),

    UserRecentActivity AS (
        SELECT
            u.Id                                    AS UserId,
            (SELECT MAX(p.CreationDate)
               FROM Posts p
              WHERE p.OwnerUserId = u.Id)          AS LastPostDate,
            (SELECT MAX(c.CreationDate)
               FROM Comments c
              WHERE c.UserId = u.Id)               AS LastCommentDate,
            (SELECT MAX(v.CreationDate)
               FROM Votes v
              WHERE v.UserId = u.Id)               AS LastVoteDate
        FROM Users u
    ),

    UserPostStats AS (
        SELECT
            p.OwnerUserId                           AS UserId,
            COUNT(*)                                AS TotalPosts,
            SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
            SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
            SUM(p.Score)                            AS ScoreSum,
            AVG(p.ViewCount)                        AS AvgViews,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId 
                               ORDER BY COUNT(*) DESC) AS PostRank
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),

    VowelRichUsers AS (
        SELECT 
            u.Id                                    AS UserId,
            u.DisplayName,
            (LENGTH(u.DisplayName)
            - LENGTH(REPLACE(LOWER(u.DisplayName), 'a', ''))
            + LENGTH(REPLACE(LOWER(u.DisplayName), 'e', ''))
            + LENGTH(REPLACE(LOWER(u.DisplayName), 'i', ''))
            + LENGTH(REPLACE(LOWER(u.DisplayName), 'o', ''))
            + LENGTH(REPLACE(LOWER(u.DisplayName), 'u', ''))) AS VowelCount
        FROM Users u
        WHERE u.DisplayName IS NOT NULL
    ),

    DuplicateLinkedUsers AS (
        SELECT DISTINCT p.OwnerUserId AS UserId
        FROM Posts p
        JOIN PostLinks pl ON pl.PostId = p.Id
        WHERE pl.LinkTypeId = 3
    ),

    ActiveInactiveSplit AS (
        SELECT 
            u.Id                                      AS UserId,
            CASE 
                WHEN ra.LastPostDate    > CAST('2024-10-01' AS DATE) - INTERVAL '180' DAY
                  OR ra.LastCommentDate > CAST('2024-10-01' AS DATE) - INTERVAL '180' DAY
                  OR ra.LastVoteDate    > CAST('2024-10-01' AS DATE) - INTERVAL '180' DAY
                THEN 'Active' 
                ELSE 'Inactive' 
            END                                        AS ActivityStatus
        FROM Users u
        LEFT JOIN UserRecentActivity ra ON ra.UserId = u.Id
    )

SELECT
    uba.UserId,
    uba.DisplayName,
    uba.Reputation,
    uba.GoldBadges,
    uba.SilverBadges,
    uba.BronzeBadges,
    uba.TotalBadges,
    COALESCE(ups.TotalPosts,0)                         AS TotalPosts,
    COALESCE(ups.Questions,0)                          AS Questions,
    COALESCE(ups.Answers,0)                            AS Answers,
    COALESCE(ups.ScoreSum,0)                           AS ScoreSum,
    COALESCE(ups.AvgViews,0)                           AS AvgViews,
    ups.PostRank                                      AS PostRankByCount,
    vr.VowelCount,
    CASE 
        WHEN dl.UserId IS NOT NULL THEN 1 
        ELSE 0 
    END                                                AS HasDuplicateLink,
    ais.ActivityStatus,
    (uba.Reputation * 0.4) +
    (uba.TotalBadges * 10) +
    (COALESCE(ups.ScoreSum,0) * 0.2) +
    (vr.VowelCount * 2) +
    (CASE ais.ActivityStatus WHEN 'Active' THEN 50 ELSE 0 END) AS PerformanceScore
FROM UserBadgeAgg uba
LEFT JOIN UserPostStats ups        ON ups.UserId = uba.UserId
LEFT JOIN VowelRichUsers vr       ON vr.UserId = uba.UserId
LEFT JOIN DuplicateLinkedUsers dl ON dl.UserId = uba.UserId
LEFT JOIN ActiveInactiveSplit ais ON ais.UserId = uba.UserId
WHERE uba.Reputation > 1000
GROUP BY
    uba.UserId,
    uba.DisplayName,
    uba.Reputation,
    uba.GoldBadges,
    uba.SilverBadges,
    uba.BronzeBadges,
    uba.TotalBadges,
    ups.TotalPosts,
    ups.Questions,
    ups.Answers,
    ups.ScoreSum,
    ups.AvgViews,
    ups.PostRank,
    vr.VowelCount,
    dl.UserId,
    ais.ActivityStatus
ORDER BY PerformanceScore DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;