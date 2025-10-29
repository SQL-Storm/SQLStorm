WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COUNT(DISTINCT p.Id) DESC) AS RankByReputationAndPostCount,
        LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) AS PreviousReputation,
        LEAD(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) AS NextReputation,
        AVG(CAST(p.Score AS DECIMAL(10,2))) AS AveragePostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.DisplayName IS NOT NULL
      AND u.AboutMe IS NOT NULL
      AND LENGTH(u.AboutMe) > 50
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserPostEngagement AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCount
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE v.VoteTypeId IN (2, 3, 5)
    GROUP BY u.Id
)
SELECT
    rua.UserId,
    rua.DisplayName,
    rua.Reputation,
    rua.PostCount,
    rua.QuestionCount,
    rua.AnswerCount,
    rua.RankByReputationAndPostCount,
    rua.PreviousReputation,
    rua.NextReputation,
    COALESCE(upe.CommentCount, 0) AS TotalComments,
    COALESCE(upe.UpVoteCount, 0) AS TotalUpVotes,
    COALESCE(upe.DownVoteCount, 0) AS TotalDownVotes,
    COALESCE(upe.FavoriteCount, 0) AS TotalFavorites,
    rua.AveragePostScore,
    (rua.Reputation - rua.PreviousReputation) AS ReputationGainFromPrevious,
    (rua.NextReputation - rua.Reputation) AS ReputationLossToNext,
    CASE
        WHEN rua.Reputation > 50000 THEN 'High Reputation'
        WHEN rua.Reputation BETWEEN 10000 AND 50000 THEN 'Medium-High Reputation'
        WHEN rua.Reputation BETWEEN 1000 AND 9999 THEN 'Medium Reputation'
        ELSE 'Low Reputation'
    END AS ReputationTier,
    CASE
        WHEN COALESCE(u.WebsiteUrl, '') <> '' THEN 'Has Website'
        ELSE 'No Website'
    END AS WebsiteStatus,
    SUBSTRING(u.AboutMe FROM 1 FOR 100) AS AboutMeSnippet,
    CASE
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Name LIKE '%Gold%') THEN 'Has Gold Badge'
        ELSE 'No Gold Badge'
    END AS HasGoldBadge,
    CASE
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) THEN 'IsDuplicateOf'
        ELSE 'NotADuplicate'
    END AS DuplicateStatus,
    p.Id AS ExamplePostId,
    p.Title AS ExamplePostTitle,
    p.CreationDate AS ExamplePostDate,
    ph.Comment AS ExamplePostHistoryComment,
    pt.Name AS ExamplePostTypeName
FROM RankedUserActivity rua
JOIN Users u ON rua.UserId = u.Id
LEFT JOIN UserPostEngagement upe ON rua.UserId = upe.UserId
LEFT JOIN Posts p ON rua.UserId = p.OwnerUserId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
WHERE p.Id IS NOT NULL
  AND rua.RankByReputationAndPostCount BETWEEN 1 AND 100
ORDER BY rua.RankByReputationAndPostCount
LIMIT 50;