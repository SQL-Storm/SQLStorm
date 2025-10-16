WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY COUNT(b.Id) DESC) AS BadgeRankByLocation,
        u.Location
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Location
    HAVING COUNT(b.Id) > 0
),
PostActivity AS (
    SELECT 
        p.OwnerUserId,
        COUNT(p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        AVG(CAST(p.Score AS DOUBLE PRECISION)) AS AvgScore,
        MAX(p.CreationDate) AS LatestPostDate,
        STRING_AGG(COALESCE(p.Tags, ''), ';') AS AllTags
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)  -- Questions and Answers
    GROUP BY p.OwnerUserId
),
TopVotedPosts AS (
    SELECT 
        v.PostId,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetVotes,
        RANK() OVER (ORDER BY COUNT(v.Id) DESC) AS VoteRank
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3)
    GROUP BY v.PostId
),
CorrelatedSubqueryExample AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments
    FROM Posts p
    WHERE EXISTS (
        SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 5  -- Edit Body
    )
),
TopPostsByOwner AS (
    SELECT p2.Id AS PostId, p2.OwnerUserId, tvp2.NetVotes, tvp2.VoteRank
    FROM Posts p2 
    INNER JOIN TopVotedPosts tvp2 ON p2.Id = tvp2.PostId
    WHERE tvp2.VoteRank <= 10
)
SELECT 
    ubs.UserId,
    u.DisplayName,
    COALESCE(ubs.BadgeCount, 0) AS BadgeCount,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    pa.PostCount,
    pa.TotalScore,
    pa.AvgScore,
    CASE 
        WHEN pa.AvgScore > 10 THEN 'High Performer'
        WHEN pa.AvgScore BETWEEN 5 AND 10 THEN 'Medium Performer'
        ELSE 'Low Performer'
    END AS PerformanceCategory,
    COALESCE(tvp.NetVotes, 0) AS MaxNetVotesOnPost,
    ubs.BadgeRankByLocation,
    UPPER(
      CASE
        WHEN u.Location IS NULL THEN NULL
        WHEN POSITION(',' IN u.Location) > 1 THEN SUBSTRING(u.Location FROM 1 FOR POSITION(',' IN u.Location) - 1)
        WHEN POSITION(',' IN u.Location) = 1 THEN ''
        ELSE u.Location
      END
    ) AS CityFromLocation,
    NULLIF(pa.AllTags, '') AS TagsList,
    u.Location AS UbsLocation,
    pa.OwnerUserId,
    tvp.PostId
FROM UserBadgeStats ubs
FULL OUTER JOIN PostActivity pa ON ubs.UserId = pa.OwnerUserId
LEFT JOIN Users u ON ubs.UserId = u.Id
LEFT JOIN TopPostsByOwner tvp ON ubs.UserId = tvp.OwnerUserId
WHERE (ubs.LatestBadgeDate > DATE '2020-01-01' OR pa.LatestPostDate > DATE '2020-01-01')
UNION
SELECT 
    c.UserId,
    u.DisplayName,
    0 AS BadgeCount,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    COUNT(c.Id) AS PostCount,  -- Using comments as proxy
    SUM(c.Score) AS TotalScore,
    AVG(CAST(c.Score AS DOUBLE PRECISION)) AS AvgScore,
    'Commenter' AS PerformanceCategory,
    0 AS MaxNetVotesOnPost,
    1 AS BadgeRankByLocation,
    NULL AS CityFromLocation,
    NULL AS TagsList,
    NULL AS UbsLocation,
    NULL AS OwnerUserId,
    NULL AS PostId
FROM Comments c
INNER JOIN Users u ON c.UserId = u.Id
LEFT JOIN CorrelatedSubqueryExample csq ON c.PostId = csq.PostId
WHERE csq.PositiveComments > 5
GROUP BY c.UserId, u.DisplayName
HAVING COUNT(c.Id) > 100
ORDER BY BadgeCount DESC, TotalScore DESC;