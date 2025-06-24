WITH UserActivity AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpVotes,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownVotes,
        COUNT(DISTINCT C.Id) AS TotalComments 
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    GROUP BY 
        U.Id, U.DisplayName
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        QuestionsAsked,
        AnswersGiven,
        TotalUpVotes,
        TotalDownVotes,
        TotalComments,
        RANK() OVER (ORDER BY TotalUpVotes - TotalDownVotes DESC) AS UserRank
    FROM 
        UserActivity
)

SELECT 
    U.UserId,
    U.DisplayName,
    U.QuestionsAsked,
    U.AnswersGiven,
    U.TotalUpVotes,
    U.TotalDownVotes,
    U.TotalComments,
    CASE 
        WHEN U.UserRank <= 10 THEN 'Top Contributor'
        ELSE 'Regular Contributor'
    END AS ContributorStatus
FROM 
    TopUsers U
WHERE 
    U.QuestionsAsked > 0 AND U.AnswersGiven > 0
ORDER BY 
    U.UserRank, U.DisplayName;

WITH RecentBadges AS (
    SELECT 
        B.UserId,
        B.Name AS BadgeName,
        B.Class,
        B.Date
    FROM 
        Badges B
    WHERE 
        B.Date > NOW() - INTERVAL '1 year'
),
UserBadgeCount AS (
    SELECT 
        R.UserId,
        COUNT(R.BadgeName) AS BadgeCount
    FROM 
        RecentBadges R
    GROUP BY 
        R.UserId
)

SELECT 
    U.UserId,
    U.DisplayName,
    COALESCE(UB.BadgeCount, 0) AS BadgeCount
FROM 
    Users U
LEFT JOIN 
    UserBadgeCount UB ON U.Id = UB.UserId
WHERE 
    U.Reputation > 100
ORDER BY 
    BadgeCount DESC, U.DisplayName;
