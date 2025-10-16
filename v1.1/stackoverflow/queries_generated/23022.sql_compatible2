WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        AVG(COALESCE(p.Score, 0)) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS LocationRank,
        u.Location
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
      AND (u.Location IS NOT NULL OR u.WebsiteUrl LIKE '%http%')
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Location
    HAVING COUNT(p.Id) > 5
),
BadgeSummary AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
TopQuestions AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
        COALESCE((SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8), 0) AS AvgBounty
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags LIKE '%<sql>%'
      AND p.CreationDate > DATE '2020-01-01'
),
RankedUsers AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.AvgPostScore,
        ua.LocationRank,
        bs.BadgeCount,
        bs.GoldBadges,
        bs.BadgeNames,
        RANK() OVER (ORDER BY ua.Reputation DESC) AS OverallRank
    FROM UserActivity ua
    LEFT JOIN BadgeSummary bs ON ua.UserId = bs.UserId
    WHERE ua.QuestionCount >= 1
      OR EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.AcceptedAnswerId IS NOT NULL)
),
CombinedResults AS (
    SELECT 
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.AvgPostScore,
        ru.OverallRank,
        ru.BadgeCount,
        COALESCE(tq.Title, 'No SQL Question') AS TopSQLQuestion,
        tq.Score AS QuestionScore,
        NULLIF(tq.PositiveComments, 0) AS PositiveComments,
        CASE 
            WHEN tq.AvgBounty > 0 THEN 'Bounty Avg: ' || CAST(tq.AvgBounty AS VARCHAR)
            ELSE 'No Bounty'
        END AS BountyInfo
    FROM RankedUsers ru
    LEFT JOIN TopQuestions tq ON tq.PostId = (
        SELECT p.Id
        FROM Posts p
        WHERE p.OwnerUserId = ru.UserId
          AND p.PostTypeId = 1
          AND p.Tags LIKE '%<sql>%'
        ORDER BY p.Score DESC
        FETCH FIRST 1 ROW ONLY
    )
    WHERE ru.OverallRank <= 100

    UNION

    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        0 AS AvgPostScore,
        CAST(NULL AS INTEGER) AS OverallRank,
        0 AS BadgeCount,
        'Inactive User' AS TopSQLQuestion,
        CAST(NULL AS INTEGER) AS QuestionScore,
        CAST(NULL AS INTEGER) AS PositiveComments,
        'N/A' AS BountyInfo
    FROM Users u
    WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
      AND u.Reputation BETWEEN 1 AND 100

    INTERSECT

    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        0 AS AvgPostScore,
        CAST(NULL AS INTEGER) AS OverallRank,
        0 AS BadgeCount,
        'Inactive User' AS TopSQLQuestion,
        CAST(NULL AS INTEGER) AS QuestionScore,
        CAST(NULL AS INTEGER) AS PositiveComments,
        'N/A' AS BountyInfo
    FROM Users u
    WHERE u.LastAccessDate < DATE '2023-01-01'
)
SELECT 
    cr.UserId,
    cr.DisplayName,
    cr.Reputation,
    cr.AvgPostScore,
    cr.OverallRank,
    cr.BadgeCount,
    UPPER(cr.TopSQLQuestion) AS UpperTitle,
    cr.QuestionScore,
    cr.PositiveComments,
    cr.BountyInfo,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = cr.UserId) AND ph.PostHistoryTypeId = 5) AS EditCount
FROM CombinedResults cr
ORDER BY cr.Reputation DESC, cr.OverallRank ASC;