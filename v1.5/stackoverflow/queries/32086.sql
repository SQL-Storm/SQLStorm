-- {"query": "32086.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 373} 
SELECT 
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.UpVotes AS TotalUpVotes,
    U.DownVotes AS TotalDownVotes,
    U.Reputation / NULLIF((U.UpVotes + U.DownVotes), 0) AS ReputationPerVote,
    (
        SELECT COUNT(*)
        FROM Posts P 
        WHERE P.OwnerUserId = U.Id
          AND P.PostTypeId = 1
          AND P.CreationDate BETWEEN '2022-01-01' AND '2022-12-31'
    ) AS PostsIn2022,
    (
        SELECT COUNT(*)
        FROM Comments C
        WHERE C.UserId = U.Id
          AND C.CreationDate BETWEEN '2022-01-01' AND '2022-12-31'
    ) AS CommentsIn2022,
    (
        SELECT COUNT(DISTINCT TagName)
        FROM Tags T
        JOIN Posts P ON P.Id = T.WikiPostId
        WHERE P.OwnerUserId = U.Id
    ) AS UniqueTagsCreated,
    (
        SELECT DISTINCT STRING_AGG(T.Name, ', ')
        FROM Badges B
        JOIN Users US ON B.UserId = US.Id
        JOIN (
            SELECT Name FROM Badges WHERE Class = 1
        ) T ON T.Name = B.Name
        WHERE US.Id = U.Id
    ) AS GoldBadgesHeld
FROM 
    Users U
WHERE 
    U.Reputation > 5000
    AND EXISTS (
        SELECT 1
        FROM Badges B
        WHERE B.UserId = U.Id
          AND B.Class = 1
    )
ORDER BY 
    ReputationPerVote DESC,
    TotalUpVotes DESC
LIMIT 50;