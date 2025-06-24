
WITH UserBadges AS (
    SELECT 
        U.Id AS UserId,
        COUNT(B.Id) AS BadgeCount,
        GROUP_CONCAT(B.Name ORDER BY B.Name SEPARATOR ', ') AS BadgeNames
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id
),
UserPostStats AS (
    SELECT 
        P.OwnerUserId,
        COUNT(P.Id) AS PostCount,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN P.PostTypeId IN (0, 4, 5) THEN 1 ELSE 0 END) AS WikiCount
    FROM 
        Posts P
    GROUP BY 
        P.OwnerUserId
),
RankedUsers AS (
    SELECT 
        U.Id,
        COALESCE(UB.BadgeCount, 0) AS BadgeCount,
        COALESCE(UPS.PostCount, 0) AS PostCount,
        UPS.QuestionCount,
        UPS.AnswerCount,
        UPS.WikiCount,
        RANK() OVER (ORDER BY COALESCE(UB.BadgeCount, 0) DESC, COALESCE(UPS.PostCount, 0) DESC) AS UserRank
    FROM 
        Users U
    LEFT JOIN 
        UserBadges UB ON U.Id = UB.UserId
    LEFT JOIN 
        UserPostStats UPS ON U.Id = UPS.OwnerUserId
)
SELECT 
    U.DisplayName,
    R.UserRank,
    R.BadgeCount,
    R.PostCount,
    R.QuestionCount,
    R.AnswerCount,
    R.WikiCount
FROM 
    RankedUsers R
JOIN 
    Users U ON R.Id = U.Id
WHERE 
    R.UserRank <= 10 
    AND R.BadgeCount > 0
ORDER BY 
    R.UserRank;
