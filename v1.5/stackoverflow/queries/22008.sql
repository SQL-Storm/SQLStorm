WITH UserStats AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        COALESCE(SUM(V.BountyAmount), 0) AS TotalBountyEarned,
        COUNT(DISTINCT P.Id) AS PostCount,
        AVG(P.Score) FILTER (WHERE P.Score IS NOT NULL) AS AvgPostScore,
        RANK() OVER (ORDER BY U.Reputation DESC) AS ReputationRank
    FROM Users U
    LEFT JOIN Votes V ON U.Id = V.UserId AND V.VoteTypeId IN (8, 9)
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    GROUP BY U.Id, U.DisplayName, U.Reputation
),
BadgeCounts AS (
    SELECT 
        B.UserId,
        COUNT(*) AS TotalBadges,
        COUNT(*) FILTER (WHERE B.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE B.Name ILIKE '%[Tt]op%' OR B.Name ILIKE '%[Aa]nswer%') AS SpecialBadges
    FROM Badges B
    WHERE B.Date > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year'
    GROUP BY B.UserId
),
PostDetails AS (
    SELECT 
        P.Id AS PostId,
        P.OwnerUserId,
        P.Score,
        P.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC) AS ScoreRank,
        CASE WHEN P.Tags IS NOT NULL THEN string_to_array(substr(P.Tags, 2, length(P.Tags) - 2), '><') END AS TagArray
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.CreationDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months'
),
CommentStats AS (
    SELECT 
        P.OwnerUserId,
        COUNT(C.Id) AS CommentCount,
        AVG(LENGTH(C.Text)) AS AvgCommentLength
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    GROUP BY P.OwnerUserId
)
SELECT 
    US.DisplayName,
    US.Reputation,
    US.TotalBountyEarned,
    US.PostCount,
    US.AvgPostScore,
    BC.TotalBadges,
    BC.GoldBadges,
    BC.SpecialBadges,
    (SELECT PD2.Score FROM PostDetails PD2 WHERE PD2.OwnerUserId = US.Id AND PD2.ScoreRank = 1) AS TopScore,
    (SELECT MAX(PD2.ViewCount) FROM PostDetails PD2 WHERE PD2.OwnerUserId = US.Id) AS TopViewCount,
    CS.CommentCount,
    CS.AvgCommentLength,
    CASE 
        WHEN US.ReputationRank <= 100 THEN 'Top 100'
        WHEN US.Reputation >= 10000 THEN 'High Rep'
        ELSE 'Others'
    END AS RepCategory,
    CONCAT(US.DisplayName, ' - ', COALESCE(string_agg(PD.TagArray[1], ', '), 'No Tags')) AS Summary
FROM UserStats US
LEFT JOIN BadgeCounts BC ON US.Id = BC.UserId
LEFT JOIN PostDetails PD ON US.Id = PD.OwnerUserId AND PD.ScoreRank = 1
LEFT JOIN CommentStats CS ON US.Id = CS.OwnerUserId
WHERE US.PostCount > 0 
   OR (COALESCE(BC.TotalBadges, 0) > 10 AND COALESCE(BC.GoldBadges, 0) > 0)
   OR (SELECT COUNT(*) FROM Posts P2 WHERE P2.OwnerUserId = US.Id AND P2.AcceptedAnswerId IS NOT NULL) > 5
GROUP BY
    US.Id,
    US.DisplayName,
    US.Reputation,
    US.TotalBountyEarned,
    US.PostCount,
    US.AvgPostScore,
    BC.TotalBadges,
    BC.GoldBadges,
    BC.SpecialBadges,
    CS.CommentCount,
    CS.AvgCommentLength,
    US.ReputationRank
ORDER BY US.Reputation DESC, US.TotalBountyEarned DESC
LIMIT 50;