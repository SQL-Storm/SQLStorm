WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.FavoriteCount,
        p.ViewCount AS PostViewCount,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostCreationDate,
        LEAD(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostCreationDate,
        AVG(CAST(p.Score AS DOUBLE PRECISION)) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS RollingAvgScore
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.PostTypeId IN (1, 2)
),
UserPostCounts AS (
    SELECT
        OwnerUserId,
        COUNT(Id) AS TotalPosts,
        COUNT(CASE WHEN PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN PostTypeId = 2 THEN 1 END) AS AnswerCount
    FROM Posts
    GROUP BY OwnerUserId
),
UserCommentStats AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        SUM(c.Score) AS TotalCommentScore,
        AVG(CAST(c.Score AS DOUBLE PRECISION)) AS AvgCommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserVoteStats AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) AS BountyStartCount
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
UserBadgeDistribution AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadgeCount,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadgeCount,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadgeCount
    FROM Badges b
    GROUP BY b.UserId
),
RecentUserActivity AS (
    SELECT
        Id AS UserId,
        MAX(LastAccessDate) AS LastLoginDate
    FROM Users
    GROUP BY Id
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.FavoriteCount,
    rp.PostViewCount,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.Views AS UserViews,
    u.UpVotes AS UserUpVotes,
    u.DownVotes AS UserDownVotes,
    upc.TotalPosts,
    upc.QuestionCount,
    upc.AnswerCount,
    ucs.TotalComments,
    ucs.TotalCommentScore,
    ucs.AvgCommentScore,
    uvs.UpVoteCount,
    uvs.DownVoteCount,
    uvs.BountyStartCount,
    ubd.GoldBadgeCount,
    ubd.SilverBadgeCount,
    ubd.BronzeBadgeCount,
    rua.LastLoginDate,
    rp.rn AS UserPostRank,
    rp.PreviousPostCreationDate,
    rp.NextPostCreationDate,
    rp.RollingAvgScore,
    CASE
        WHEN rp.PostScore > 100 THEN 'High Score'
        WHEN rp.PostScore > 50 THEN 'Medium Score'
        ELSE 'Low Score'
    END AS ScoreCategory,
    SUBSTRING(rp.PostTypeName FROM 1 FOR 3) AS PostTypeAbbreviation,
    COALESCE(u.Location, 'Unknown Location') AS UserLocation,
    (rp.PostScore + COALESCE(rp.FavoriteCount, 0)) * COALESCE(rp.PostViewCount, 0) AS EngagementFactor,
    CASE WHEN rp.PostTypeName LIKE '%Question%' AND rp.PostScore < 0 THEN 'Negative Question Score' ELSE NULL END AS NegativeQuestionFlag
FROM RankedPosts rp
JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN UserPostCounts upc ON rp.OwnerUserId = upc.OwnerUserId
LEFT JOIN UserCommentStats ucs ON rp.OwnerUserId = ucs.UserId
LEFT JOIN UserVoteStats uvs ON rp.OwnerUserId = uvs.UserId
LEFT JOIN UserBadgeDistribution ubd ON rp.OwnerUserId = ubd.UserId
LEFT JOIN RecentUserActivity rua ON rp.OwnerUserId = rua.UserId
WHERE rp.rn <= 100
  AND rp.PostCreationDate BETWEEN (cast('2024-10-01' as date) - INTERVAL '1 year') AND cast('2024-10-01' as date)
  AND COALESCE(u.Location, '') <> ''
  AND rp.PostScore > (
      SELECT AVG(p2.Score)
      FROM Posts p2
      WHERE p2.PostTypeId = rp.PostTypeId
  )
ORDER BY rp.PostCreationDate DESC, rp.PostScore DESC;