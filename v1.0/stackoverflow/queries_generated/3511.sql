WITH UserActivity AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(CM.Id) AS CommentCount,
        SUM(COALESCE(V.BountyAmount, 0)) AS TotalBounty,
        AVG(U.Reputation) OVER() AS AvgReputation
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Comments CM ON U.Id = CM.UserId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (8, 9) -- BountyStart and BountyClose
    GROUP BY 
        U.Id, U.DisplayName
),
PostDetails AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        P.CreationDate,
        P.Score,
        COALESCE((SELECT SUM(VoteTypeId = 2) FROM Votes WHERE PostId = P.Id), 0) AS UpVotes,
        COALESCE((SELECT SUM(VoteTypeId = 3) FROM Votes WHERE PostId = P.Id), 0) AS DownVotes,
        P.ViewCount,
        P.AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.CreationDate DESC) AS PostRank
    FROM 
        Posts P
    WHERE 
        P.CreationDate >= NOW() - INTERVAL '1 year'
),
TopPosts AS (
    SELECT 
        PD.* 
    FROM 
        PostDetails PD
    WHERE 
        PD.PostRank <= 5
)
SELECT 
    UA.DisplayName,
    UA.QuestionCount,
    UA.AnswerCount,
    UA.CommentCount,
    UA.TotalBounty,
    TP.Title,
    TP.CreationDate,
    TP.Score,
    TP.UpVotes,
    TP.DownVotes,
    TP.ViewCount
FROM 
    UserActivity UA
LEFT JOIN 
    TopPosts TP ON UA.UserId = TP.OwnerUserId
WHERE 
    UA.Reputation > (SELECT AVG(Reputation) FROM Users) 
ORDER BY 
    UA.TotalBounty DESC NULLS LAST, UA.CommentCount DESC;
