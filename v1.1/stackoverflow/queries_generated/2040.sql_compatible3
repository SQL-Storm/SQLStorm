WITH RecentUsers AS (
    SELECT U.Id, U.DisplayName, U.Reputation, U.CreationDate
    FROM Users U
    WHERE U.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
),
HighReputationUsers AS (
    SELECT Id, DisplayName, Reputation
    FROM RecentUsers
    WHERE Reputation > 1000
),
TopVotedAnswers AS (
    SELECT P.Id, P.Title, MAX(V.MaxVotes) AS MaxVotes
    FROM Posts P
    JOIN (
        SELECT PostId, COUNT(*) AS MaxVotes
        FROM Votes
        WHERE VoteTypeId = 2
        GROUP BY PostId
    ) V ON P.Id = V.PostId
    WHERE P.PostTypeId = 2
    GROUP BY P.Id, P.Title
),
TopQuestions AS (
    SELECT P.Id, P.Title, P.Score, P.OwnerUserId, U.DisplayName
    FROM Posts P
    LEFT JOIN Users U ON P.OwnerUserId = U.Id
    WHERE P.PostTypeId = 1 AND P.Score > 10
    -- ORDER BY removed from CTE for portability; ordering should be applied in the outer query
),
UserBadgeCounts AS (
    SELECT B.UserId, COUNT(*) AS BadgeCount
    FROM Badges B
    GROUP BY B.UserId
),
ComplexQuery AS (
    SELECT H.DisplayName AS UserName,
           H.Reputation,
           T.Title AS QuestionTitle,
           T.Score AS QuestionScore,
           COALESCE(BC.BadgeCount, 0) AS NumBadges,
           CASE
             -- remove postgres-specific pg_catalog checks; use portable fallback: absolute length difference
             WHEN 1 = 0 THEN NULL
             ELSE ABS(LENGTH(T.Title) - LENGTH(A.Title))
           END AS TitleSimilarity,
           H.Id AS H_Id,
           T.OwnerUserId AS T_OwnerUserId,
           A.Id AS A_Id,
           A.Title AS A_Title
    FROM HighReputationUsers H
    JOIN TopQuestions T ON H.Id = T.OwnerUserId
    LEFT JOIN UserBadgeCounts BC ON H.Id = BC.UserId
    CROSS JOIN TopVotedAnswers A
    WHERE T.OwnerUserId IN (SELECT Id FROM RecentUsers)
      AND H.Reputation > 1.5 * (SELECT AVG(U2.Reputation) FROM Users U2)
    GROUP BY H.DisplayName, H.Reputation, T.Title, T.Score, BC.BadgeCount, A.Title, H.Id, T.OwnerUserId, A.Id
)
SELECT UserName, QuestionTitle, QuestionScore, NumBadges, TitleSimilarity
FROM ComplexQuery
WHERE NumBadges > 5
  AND TitleSimilarity < 10
ORDER BY QuestionScore DESC, NumBadges ASC
LIMIT 50;