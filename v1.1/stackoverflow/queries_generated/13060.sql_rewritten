-- {"query": "13060.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 751} 
WITH HighReputationUsers AS (
    SELECT Id, Reputation, DisplayName, Location
    FROM Users
    WHERE Reputation > (SELECT AVG(Reputation) FROM Users) * 1.5
),
UserPosts AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        COUNT(c.Id) AS CommentCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1 AND p.CreationDate > '2020-01-01'
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate, p.Tags
),
TopPosts AS (
    SELECT 
        up.Id,
        up.OwnerUserId,
        up.Score,
        up.ViewCount,
        up.CreationDate,
        up.Tags,
        up.CommentCount,
        DENSE_RANK() OVER (PARTITION BY up.OwnerUserId ORDER BY up.Score DESC) AS Rank
    FROM UserPosts up
    WHERE up.OwnerUserId IN (SELECT Id FROM HighReputationUsers)
),
UserBadges AS (
    SELECT 
        u.Id AS UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
FinalUserStats AS (
    SELECT 
        hru.DisplayName,
        hru.Location,
        hru.Reputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        SUM(tp.Score) AS TotalScore,
        AVG(tp.ViewCount) AS AvgViewCount,
        MAX(tp.CreationDate) AS LastPostDate,
        STRING_AGG(DISTINCT CASE WHEN tp.Tags IS NOT NULL THEN REGEXP_REPLACE(tp.Tags, '<.*?>', '', 'g') END, ', ') AS TagList
    FROM HighReputationUsers hru
    JOIN UserBadges ub ON hru.Id = ub.UserId
    LEFT JOIN TopPosts tp ON hru.Id = tp.OwnerUserId AND tp.Rank <= 3
    GROUP BY hru.Id, hru.DisplayName, hru.Location, hru.Reputation, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges
)
SELECT 
    DisplayName,
    Location,
    Reputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    TotalScore,
    AvgViewCount,
    LastPostDate,
    TagList
FROM FinalUserStats
WHERE AvgViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1)
ORDER BY TotalScore DESC
LIMIT 10;