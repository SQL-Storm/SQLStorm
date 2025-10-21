WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) AS TotalQuestionScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) AS TotalAnswerScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId IN (1,2) THEN p.Id END) AS TotalPosts,
        COALESCE(AVG(CASE WHEN c.PostId IS NOT NULL THEN c.Score END), 0) AS AvgCommentScoreOnPosts,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostRankPerUser
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON p.Id = c.PostId AND c.UserId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopPosts AS (
    SELECT DISTINCT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.Title,
        REPLACE(COALESCE(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), ''), '><', ',') AS TagString,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS RankByScore
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 0
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalQuestionScore + ua.TotalAnswerScore AS TotalScore,
    ua.TotalPosts,
    ua.AvgCommentScoreOnPosts,
    ua.TotalBadges,
    tp.TagString AS TopQuestionTags,
    CASE 
        WHEN ua.Reputation > 10000 THEN 'Expert'
        WHEN ua.Reputation > 1000 THEN 'Contributor'
        ELSE 'Newbie'
    END AS UserCategory,
    COALESCE(SUM(ua.Reputation * 1.0 / NULLIF(ua.TotalPosts, 0)), 0) AS AdjustedRepPerPost,
    RANK() OVER (ORDER BY 
        (ua.TotalQuestionScore + ua.TotalAnswerScore) DESC,
        ua.TotalBadges DESC
    ) AS OverallRank
FROM UserActivity ua
LEFT JOIN TopPosts tp ON ua.UserId = tp.OwnerUserId AND tp.RankByScore = 1
WHERE ua.TotalPosts > 0
  AND EXISTS (
      SELECT 1 
      FROM Votes v 
      WHERE v.PostId IN (
          SELECT p.Id 
          FROM Posts p 
          WHERE p.OwnerUserId = ua.UserId AND p.PostTypeId = 1
      ) 
      AND v.VoteTypeId IN (2,3) 
      AND v.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
  )
GROUP BY 
    ua.UserId, 
    ua.DisplayName, 
    ua.Reputation, 
    ua.TotalQuestionScore, 
    ua.TotalAnswerScore, 
    ua.TotalPosts, 
    ua.AvgCommentScoreOnPosts, 
    ua.TotalBadges, 
    tp.TagString
HAVING COUNT(CASE WHEN ua.PostRankPerUser = 1 THEN 1 END) > 0
ORDER BY OverallRank
LIMIT 100;