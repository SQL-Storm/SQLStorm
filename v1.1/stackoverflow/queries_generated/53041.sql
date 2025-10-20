-- {"query": "53041.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 782} 

WITH RecentPosts AS (
    SELECT 
        p.Id AS PostId, 
        p.PostTypeId, 
        p.OwnerUserId, 
        p.Score, 
        p.CreationDate,
        CASE 
            WHEN p.PostTypeId = 1 THEN p.Tags 
            ELSE (SELECT Tags FROM Posts q WHERE q.Id = p.ParentId) 
        END AS EffectiveTags
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
),
TagPopularity AS (
    SELECT 
        t.Id AS TagId, 
        t.TagName, 
        COUNT(DISTINCT rp.PostId) AS TagQuestionCount,
        SUM(rp.Score) AS TotalTagScore
    FROM Tags t
    JOIN RecentPosts rp ON rp.EffectiveTags LIKE '%' || t.TagName || '%'
    WHERE rp.PostTypeId IN (1, 2)
    GROUP BY t.Id, t.TagName
    HAVING COUNT(DISTINCT rp.PostId) > 1000
),
UserContributions AS (
    SELECT 
        u.Id AS UserId, 
        u.Reputation, 
        u.DisplayName,
        COUNT(DISTINCT rp.PostId) AS TotalPosts,
        SUM(rp.Score) AS TotalScore,
        AVG(rp.Score) AS AvgScore,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT SUM(v.BountyAmount) FROM Votes v JOIN Posts vp ON v.PostId = vp.Id WHERE v.VoteTypeId = 9 AND vp.OwnerUserId = u.Id) AS TotalBountiesEarned
    FROM Users u
    JOIN RecentPosts rp ON u.Id = rp.OwnerUserId
    WHERE rp.PostTypeId IN (1, 2)
    GROUP BY u.Id, u.Reputation, u.DisplayName
),
UserTagSpecialization AS (
    SELECT 
        uc.UserId,
        tp.TagName,
        COUNT(DISTINCT rp.PostId) AS PostsInTag,
        SUM(rp.Score) AS ScoreInTag,
        ROW_NUMBER() OVER (PARTITION BY uc.UserId ORDER BY SUM(rp.Score) DESC) AS TagRank
    FROM UserContributions uc
    JOIN RecentPosts rp ON uc.UserId = rp.OwnerUserId
    JOIN TagPopularity tp ON rp.EffectiveTags LIKE '%' || tp.TagName || '%'
    GROUP BY uc.UserId, tp.TagName
),
TopUsersPerTag AS (
    SELECT 
        uts.TagName,
        uts.UserId,
        uc.DisplayName,
        uts.ScoreInTag,
        uc.TotalScore,
        uc.GoldBadges,
        uc.TotalBountiesEarned,
        RANK() OVER (PARTITION BY uts.TagName ORDER BY uts.ScoreInTag DESC) AS UserRankInTag
    FROM UserTagSpecialization uts
    JOIN UserContributions uc ON uts.UserId = uc.UserId
    WHERE uts.TagRank = 1
)
SELECT 
    tupt.TagName,
    tp.TagQuestionCount,
    tp.TotalTagScore,
    tupt.DisplayName AS TopUser,
    tupt.ScoreInTag AS TopUserScoreInTag,
    tupt.TotalScore AS TopUserTotalScore,
    tupt.GoldBadges,
    tupt.TotalBountiesEarned,
    (SELECT COUNT(*) FROM Comments c JOIN Posts cp ON c.PostId = cp.Id WHERE cp.OwnerUserId = tupt.UserId AND c.Score > 5) AS HighScoreComments
FROM TopUsersPerTag tupt
JOIN TagPopularity tp ON tupt.TagName = tp.TagName
WHERE tupt.UserRankInTag = 1
ORDER BY tp.TotalTagScore DESC
LIMIT 50;
