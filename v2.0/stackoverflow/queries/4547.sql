WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRank,
        DENSE_RANK() OVER (ORDER BY u.CreationDate ASC) AS UserCreationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE u.DisplayName IS NOT NULL AND u.DisplayName NOT LIKE '%Deleted%'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostInteraction AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        pt.Name AS PostType,
        CASE
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Accepted Answered'
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Has Answers'
            WHEN p.PostTypeId = 1 AND p.AnswerCount = 0 THEN 'No Answers'
            ELSE 'Other'
        END AS QuestionStatus,
        COALESCE(p.FavoriteCount, 0) AS Favorites,
        COALESCE(p.CommentCount, 0) AS Comments,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserPostScore,
        SUM(p.ViewCount) OVER (PARTITION BY p.OwnerUserId) AS TotalUserViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS LastActivityRank
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL
)
SELECT
    rua.DisplayName,
    rua.Reputation,
    rua.CreationDate AS UserCreationDate,
    rua.ReputationRank,
    rua.UserCreationRank,
    pi.PostId,
    pi.PostType,
    pi.PostCreationDate,
    pi.Score AS PostScore,
    pi.ViewCount AS PostViewCount,
    pi.QuestionStatus,
    pi.Favorites,
    pi.Comments,
    pi.UserPostRank,
    pi.AvgUserPostScore,
    pi.TotalUserViewCount,
    pi.LastActivityRank,
    CASE
        WHEN pi.Score > 100 THEN 'High Score'
        WHEN pi.Score BETWEEN 10 AND 100 THEN 'Medium Score'
        ELSE 'Low Score'
    END AS ScoreCategory,
    SUBSTRING(pi.PostType FROM 1 FOR 1) || '-' || CAST(pi.UserPostRank AS VARCHAR) AS PostTypeAndRank,
    (rua.DisplayName || ' (' || CAST(rua.Reputation AS VARCHAR) || ')') AS UserDisplayNameAndReputation,
    (pi.Score * 1.0 / NULLIF(pi.ViewCount, 0)) * 1000 AS ScorePerThousandViews,
    CASE
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = rua.UserId AND b.Name LIKE '%Expert%') THEN TRUE
        ELSE FALSE
    END AS HasExpertBadge,
    UPPER(pi.PostType) AS UppercasePostType
FROM RankedUserActivity rua
INNER JOIN PostInteraction pi ON rua.UserId = pi.OwnerUserId
WHERE
    rua.Reputation > 500
    AND pi.UserPostRank <= 5
    AND pi.PostCreationDate >= DATE '2023-01-01'
    AND (pi.PostType = 'Question' OR pi.PostType = 'Answer')
    AND pi.Score > 0
    AND pi.ViewCount IS NOT NULL
    AND pi.AvgUserPostScore > pi.Score * 0.5
GROUP BY
    rua.DisplayName,
    rua.Reputation,
    rua.CreationDate,
    rua.ReputationRank,
    rua.UserCreationRank,
    rua.UserId,
    pi.PostId,
    pi.PostType,
    pi.PostCreationDate,
    pi.Score,
    pi.ViewCount,
    pi.QuestionStatus,
    pi.Favorites,
    pi.Comments,
    pi.UserPostRank,
    pi.AvgUserPostScore,
    pi.TotalUserViewCount,
    pi.LastActivityRank
ORDER BY
    rua.Reputation DESC,
    rua.CreationDate ASC,
    pi.UserPostRank ASC;