
WITH UserStats AS (
    SELECT 
        Id AS UserId,
        DisplayName,
        Reputation,
        CreationDate,
        UpVotes,
        DownVotes,
        Views,
        CAST((UpVotes - DownVotes) AS INT) AS NetVotes
    FROM 
        Users
), 
PostStats AS (
    SELECT 
        Id AS PostId,
        OwnerUserId,
        Score,
        ViewCount,
        CommentCount,
        AnswerCount,
        CreationDate,
        LastActivityDate,
        Title,
        (SELECT COUNT(*) FROM Comments WHERE PostId = Posts.Id) AS TotalComments,
        (SELECT COUNT(*) FROM Votes WHERE PostId = Posts.Id) AS TotalVotes
    FROM 
        Posts
    WHERE 
        CreationDate >= DATEADD(day, -30, '2024-10-01 12:34:56')
), 
UserPostStats AS (
    SELECT 
        U.UserId,
        U.DisplayName,
        COUNT(P.PostId) AS PostCount,
        SUM(P.Score) AS TotalScore,
        SUM(P.ViewCount) AS TotalViews,
        AVG(P.ViewCount) AS AverageViewsPerPost
    FROM 
        UserStats U
    JOIN 
        PostStats P ON U.UserId = P.OwnerUserId
    GROUP BY 
        U.UserId, U.DisplayName
)
SELECT 
    UPS.UserId,
    UPS.DisplayName,
    UPS.PostCount,
    UPS.TotalScore,
    UPS.TotalViews,
    UPS.AverageViewsPerPost,
    U.Reputation,
    U.CreationDate
FROM 
    UserPostStats UPS
JOIN 
    Users U ON UPS.UserId = U.Id
ORDER BY 
    UPS.TotalScore DESC, 
    UPS.TotalViews DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
