WITH RECURSIVE UserPostCounts AS (
    SELECT 
        U.Id AS UserId, 
        U.DisplayName, 
        COUNT(P.Id) AS PostCount,
        ROW_NUMBER() OVER (ORDER BY COUNT(P.Id) DESC) AS Rank
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
        AND P.PostTypeId IN (1, 2)
    GROUP BY 
        U.Id, U.DisplayName
),
TopUsers AS (
    SELECT 
        UserId, 
        DisplayName, 
        PostCount
    FROM 
        UserPostCounts
    WHERE 
        Rank <= 10
),
UserBadgeCounts AS (
    SELECT 
        U.Id AS UserId, 
        COUNT(B.Id) AS BadgeCount
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id
),
UserActivity AS (
    SELECT 
        U.UserId, 
        U.DisplayName, 
        UPC.PostCount, 
        COALESCE(UBC.BadgeCount, 0) AS BadgeCount, 
        COUNT(DISTINCT C.Id) AS CommentCount
    FROM 
        TopUsers U
    JOIN 
        UserPostCounts UPC ON U.UserId = UPC.UserId
    LEFT JOIN 
        UserBadgeCounts UBC ON U.UserId = UBC.UserId
    LEFT JOIN 
        Comments C ON U.UserId = C.UserId
    GROUP BY 
        U.UserId, U.DisplayName, UPC.PostCount, COALESCE(UBC.BadgeCount, 0)
),
PostScores AS (
    SELECT 
        P.OwnerUserId, 
        AVG(P.Score) AS AvgPostScore
    FROM 
        Posts P
    WHERE 
        P.PostTypeId IN (1, 2)
    GROUP BY 
        P.OwnerUserId
),
UserScores AS (
    SELECT 
        UA.UserId, 
        UA.DisplayName, 
        UA.PostCount, 
        UA.BadgeCount, 
        UA.CommentCount, 
        COALESCE(PS.AvgPostScore, 0) AS AvgPostScore
    FROM 
        UserActivity UA
    LEFT JOIN 
        PostScores PS ON UA.UserId = PS.OwnerUserId
)
SELECT 
    US.UserId, 
    US.DisplayName, 
    US.PostCount, 
    US.BadgeCount, 
    US.CommentCount, 
    US.AvgPostScore
FROM 
    UserScores US
ORDER BY 
    US.PostCount DESC, 
    US.BadgeCount DESC, 
    US.CommentCount DESC, 
    US.AvgPostScore DESC;