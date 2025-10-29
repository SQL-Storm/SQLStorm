-- {"query": "4191.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1238} 
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
        LAG(p.CreationDate, 1, NULL) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostCreationDate,
        LEAD(p.CreationDate, 1, NULL) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostCreationDate,
        AVG(CAST(p.Score AS FLOAT)) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS RollingAvgScore
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
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
        AVG(CAST(c.Score AS FLOAT)) AS AvgCommentScore
    FROM Comments AS c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserVoteStats AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) AS BountyStartCount
    FROM Votes AS v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
UserBadgeDistribution AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadgeCount,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadgeCount,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadgeCount
    FROM Badges AS b
    GROUP BY b.UserId
),
RecentUserActivity AS (
    SELECT
        UserId,
        MAX(LastAccessDate) AS LastLoginDate
    FROM Users
    GROUP BY UserId
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
    SUBSTRING(rp.PostTypeName, 1, 3) AS PostTypeAbbreviation,
    COALESCE(u.Location, 'Unknown Location') AS UserLocation,
    (rp.PostScore + rp.FavoriteCount) * rp.PostViewCount AS EngagementFactor,
    CASE WHEN rp.PostTypeName LIKE '%Question%' AND rp.PostScore < 0 THEN 'Negative Question Score' ELSE NULL END AS NegativeQuestionFlag
FROM RankedPosts AS rp
JOIN Users AS u ON rp.OwnerUserId = u.Id
LEFT JOIN UserPostCounts AS upc ON rp.OwnerUserId = upc.OwnerUserId
LEFT JOIN UserCommentStats AS ucs ON rp.OwnerUserId = ucs.UserId
LEFT JOIN UserVoteStats AS uvs ON rp.OwnerUserId = uvs.UserId
LEFT JOIN UserBadgeDistribution AS ubd ON rp.OwnerUserId = ubd.UserId
LEFT JOIN RecentUserActivity AS rua ON rp.OwnerUserId = rua.UserId
WHERE rp.rn <= 100
  AND rp.PostCreationDate BETWEEN DATE('now', '-1 year') AND DATE('now')
  AND COALESCE(u.Location, '') <> ''
  AND rp.PostScore > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = rp.PostTypeId)
ORDER BY rp.PostCreationDate DESC, rp.PostScore DESC;