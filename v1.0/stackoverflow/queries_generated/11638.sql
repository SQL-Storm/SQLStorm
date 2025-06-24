WITH UserStats AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(V.VoteTypeId = 2) AS TotalUpVotes,
        SUM(V.VoteTypeId = 3) AS TotalDownVotes,
        SUM(B.Id IS NOT NULL) AS TotalBadges
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
),

PostStats AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        P.CreationDate,
        P.ViewCount,
        P.Score,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        U.DisplayName AS OwnerName,
        CASE 
            WHEN P.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            ELSE 'Unaccepted'
        END AS AnswerStatus
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
)

SELECT 
    US.UserId,
    US.DisplayName,
    US.Reputation,
    US.TotalPosts,
    US.TotalQuestions,
    US.TotalAnswers,
    US.TotalUpVotes,
    US.TotalDownVotes,
    US.TotalBadges,
    PS.PostId,
    PS.Title,
    PS.CreationDate,
    PS.ViewCount,
    PS.Score,
    PS.AnswerCount,
    PS.CommentCount,
    PS.FavoriteCount,
    PS.OwnerName,
    PS.AnswerStatus
FROM 
    UserStats US
LEFT JOIN 
    PostStats PS ON US.UserId = PS.OwnerUserId
ORDER BY 
    US.Reputation DESC, PS.ViewCount DESC;
