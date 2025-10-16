-- {"query": "1099.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 550} 

WITH UserReputation AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        RANK() OVER (ORDER BY U.Reputation DESC) AS ReputationRank
    FROM 
        Users U
),
ClosedPosts AS (
    SELECT 
        P.Id AS PostId,
        P.Title AS PostTitle,
        P.CreationDate,
        P.ClosedDate,
        COUNT(V.Id) AS VoteCount
    FROM 
        Posts P
    LEFT JOIN 
        PostHistory PH ON P.Id = PH.PostId AND PH.PostHistoryTypeId IN (10, 11) -- Closed or Reopened
    LEFT JOIN 
        Votes V ON P.Id = V.PostId AND V.VoteTypeId = 6  -- Close votes
    WHERE 
        P.ClosedDate IS NOT NULL
    GROUP BY 
        P.Id
),
PostComments AS (
    SELECT 
        C.PostId,
        COUNT(C.Id) AS CommentCount
    FROM 
        Comments C
    GROUP BY 
        C.PostId
),
TopUsers AS (
    SELECT 
        U.UserId,
        UR.DisplayName,
        SUM(COALESCE(PV.VoteCount, 0)) AS TotalVoteCount,
        SUM(COALESCE(PC.CommentCount, 0)) AS TotalCommentCount
    FROM 
        UserReputation UR
    LEFT JOIN 
        Posts P ON P.OwnerUserId = UR.UserId
    LEFT JOIN 
        ClosedPosts PV ON PV.PostId = P.Id
    LEFT JOIN 
        PostComments PC ON PC.PostId = P.Id
    WHERE 
        UR.ReputationRank <= 10
    GROUP BY 
        U.UserId, UR.DisplayName
),
FinalResult AS (
    SELECT 
        T.Users.DisplayName,
        T.TotalVoteCount,
        T.TotalCommentCount,
        CASE 
            WHEN T.TotalVoteCount > 100 THEN 'Highly Active'
            WHEN T.TotalVoteCount BETWEEN 50 AND 100 THEN 'Moderately Active'
            ELSE 'Less Active'
        END AS ActivityLevel
    FROM 
        TopUsers T
)
SELECT 
    FR.DisplayName,
    FR.TotalVoteCount,
    FR.TotalCommentCount,
    FR.ActivityLevel,
    (SELECT COUNT(*) FROM Posts P WHERE P.OwnerUserId = U.UserId AND P.CreationDate > CURRENT_TIMESTAMP - INTERVAL '1 year') AS PostsInLastYear
FROM 
    FinalResult FR
LEFT JOIN 
    Users U ON FR.DisplayName = U.DisplayName
ORDER BY 
    FR.TotalVoteCount DESC, 
    FR.TotalCommentCount DESC;
