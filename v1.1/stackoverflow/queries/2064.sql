-- {"query": "2064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 474} 
WITH UserReputation AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC) AS ReputationRank
    FROM Users U
),
RecentActivity AS (
    SELECT 
        PostId, 
        MAX(CreationDate) AS LastActivityDate
    FROM (
        SELECT 
            P.Id AS PostId,
            P.LastActivityDate AS CreationDate
        FROM Posts P
        WHERE P.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'

        UNION ALL

        SELECT 
            C.PostId,
            C.CreationDate
        FROM Comments C
        WHERE C.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    ) AS Activity
    GROUP BY PostId
),
TopQuestions AS (
    SELECT
        P.Id AS QuestionId,
        P.Title,
        P.Score,
        COUNT(A.Id) AS AnswerCount,
        COALESCE(SUM(VOTE.VoteCount), 0) AS TotalVotes
    FROM Posts P
    LEFT JOIN Posts A ON A.ParentId = P.Id AND A.PostTypeId = 2
    LEFT JOIN (
        SELECT 
            PostId, 
            COUNT(*) AS VoteCount
        FROM Votes 
        WHERE VoteTypeId IN (2, 3) 
        GROUP BY PostId
    ) VOTE ON VOTE.PostId = P.Id
    WHERE P.PostTypeId = 1
    GROUP BY P.Id, P.Title, P.Score
    HAVING COUNT(A.Id) > 0 AND COALESCE(SUM(VOTE.VoteCount), 0) > 10
)
SELECT 
    QU.QuestionId,
    U.DisplayName,
    U.Reputation,
    QU.Title,
    RA.LastActivityDate,
    QU.Score,
    QU.AnswerCount,
    QU.TotalVotes
FROM TopQuestions QU
JOIN Users U ON U.Id = (SELECT U2.Id FROM Posts P JOIN Users U2 ON P.OwnerUserId = U2.Id WHERE P.Id = QU.QuestionId)
JOIN RecentActivity RA ON RA.PostId = QU.QuestionId
WHERE RA.LastActivityDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months'
ORDER BY QU.Score DESC;