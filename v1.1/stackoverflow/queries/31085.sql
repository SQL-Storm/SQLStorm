WITH UserStats AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        COUNT(DISTINCT P.Id) AS PostCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        COALESCE(SUM(V.BountyAmount), 0) AS TotalBounty
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Votes V ON V.UserId = U.Id
    WHERE 
        U.Reputation > 1000
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
),
PostDetails AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        P.CreationDate,
        P.ViewCount,
        COALESCE(COUNT(CM.Id), 0) AS CommentCount,
        COALESCE(SUM(Vt.VoteTypeId /* score not available; summing VoteTypeId as a surrogate or adjust as needed */), 0) AS VoteScore,
        COUNT(DISTINCT PH.Id) AS HistoryCount
    FROM 
        Posts P
    LEFT JOIN 
        Comments CM ON P.Id = CM.PostId
    LEFT JOIN 
        Votes Vt ON P.Id = Vt.PostId
    LEFT JOIN 
        PostHistory PH ON P.Id = PH.PostId
    WHERE 
        P.CreationDate > DATE '2021-01-01'
    GROUP BY 
        P.Id, P.Title, P.CreationDate, P.ViewCount
),
TopUsers AS (
    SELECT 
        US.UserId,
        US.DisplayName,
        US.PostCount,
        US.AnswerCount,
        US.QuestionCount,
        US.TotalBounty,
        ROW_NUMBER() OVER (ORDER BY US.PostCount DESC) AS Rank
    FROM 
        UserStats US
    WHERE 
        US.PostCount > 5
)
SELECT 
    TU.DisplayName AS TopUser,
    TU.PostCount,
    TU.AnswerCount,
    TU.QuestionCount,
    TU.TotalBounty,
    PD.Title AS RecentPost,
    PD.ViewCount,
    PD.CommentCount,
    PD.VoteScore,
    PD.HistoryCount
FROM 
    TopUsers TU
JOIN 
    Posts P ON P.OwnerUserId = TU.UserId
JOIN
    PostDetails PD ON PD.PostId = P.Id
WHERE 
    TU.Rank <= 10
ORDER BY 
    TU.Rank, PD.CreationDate DESC;