WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        AVG(p.Score) AS AvgPostScore,
        DENSE_RANK() OVER (ORDER BY COUNT(b.Id) DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
PostInteractions AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Tags,
        CAST(v.VoteTypeId AS INTEGER) AS VoteTypeId,
        COUNT(DISTINCT v.UserId) AS UniqueVoters,
        MAX(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS HasUpvotes,
        ROW_NUMBER() OVER (PARTITION BY p.Tags ORDER BY COUNT(v.Id) DESC) AS TagPopularity
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1 
      AND p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 years'
    GROUP BY p.Id, p.Title, p.Tags, CAST(v.VoteTypeId AS INTEGER)
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.TotalBadges,
    pi.Title,
    pi.Tags,
    pi.UniqueVoters,
    ubs.AvgPostScore,
    COALESCE(pi.HasUpvotes, 0) AS HasUpvotes,
    (SELECT COUNT(*) 
     FROM Comments c 
     WHERE c.UserId = ubs.UserId 
       AND c.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year') AS YearComments,
    CASE 
        WHEN ubs.GoldBadges > 5 AND pi.UniqueVoters > 10 THEN 'High Impact'
        WHEN ubs.SilverBadges > 3 THEN 'Moderate Impact'
        ELSE 'Low Impact'
    END AS UserContributionLevel
FROM UserBadgeStats ubs
JOIN PostInteractions pi ON pi.VoteTypeId IS NOT NULL
WHERE ubs.BadgeRank <= 100
    AND (pi.UniqueVoters > 5 OR ubs.AvgPostScore > 3)
ORDER BY ubs.TotalBadges DESC, pi.UniqueVoters DESC
LIMIT 500;