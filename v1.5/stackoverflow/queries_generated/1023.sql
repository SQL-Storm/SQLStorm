-- {"query": "1023.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 358} 

WITH UserReputation AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        RANK() OVER (ORDER BY U.Reputation DESC) AS ReputationRank
    FROM Users U
),
PostStatistics AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        P.PostTypeId,
        COUNT(C.Id) AS CommentCount,
        COUNT(V.Id) AS VoteCount,
        MAX(COALESCE(P.AcceptedAnswerId, 0)) AS HasAcceptedAnswer
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (2, 3) -- Upvote and downvote
    GROUP BY P.Id, P.Title, P.PostTypeId
),
FilteredPosts AS (
    SELECT 
        PS.PostId,
        PS.Title,
        PS.PostTypeId,
        PS.CommentCount,
        PS.VoteCount,
        CASE 
            WHEN PS.HasAcceptedAnswer > 0 THEN 'Yes' 
            ELSE 'No' 
        END AS AcceptedAnswer
    FROM PostStatistics PS
    WHERE PS.CommentCount > 5 AND PS.VoteCount > 10
)
SELECT 
    U.DisplayName,
    U.Reputation,
    FR.PostId,
    FR.Title,
    FR.AcceptedAnswer
FROM UserReputation U
INNER JOIN FilteredPosts FR ON U.UserId = (SELECT OwnerUserId FROM Posts WHERE Posts.Id = FR.PostId)
WHERE U.Reputation > (SELECT AVG(Reputation) FROM UserReputation)
ORDER BY U.Reputation DESC, FR.VoteCount DESC
LIMIT 10;
