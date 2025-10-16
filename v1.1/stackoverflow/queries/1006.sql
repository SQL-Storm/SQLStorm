WITH UserStatistics AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        COUNT(DISTINCT P.Id) AS PostCount,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE U.Reputation > 100
    GROUP BY U.Id, U.DisplayName, U.Reputation
),
RankedUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        QuestionCount,
        AnswerCount,
        RANK() OVER (ORDER BY Reputation DESC) AS UserRank
    FROM UserStatistics
)
SELECT 
    U.UserRank,
    U.DisplayName,
    U.Reputation,
    COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpVotes,
    COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownVotes,
    COALESCE(B.BadgeCount, 0) AS TotalBadges,
    COUNT(DISTINCT PH.Id) AS PostHistoryCount
FROM RankedUsers U
LEFT JOIN Votes V ON V.UserId = U.UserId
LEFT JOIN (
    SELECT 
        UserId,
        COUNT(*) AS BadgeCount 
    FROM Badges 
    GROUP BY UserId
) B ON B.UserId = U.UserId
LEFT JOIN PostHistory PH ON PH.UserId = U.UserId
WHERE U.UserRank <= 10
GROUP BY U.UserRank, U.DisplayName, U.Reputation, B.BadgeCount
ORDER BY U.Reputation DESC;