-- {"query": "31069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 362} 

WITH UserActivity AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        COUNT(DISTINCT P.Id) AS PostCount,
        COUNT(DISTINCT C.Id) AS CommentCount,
        SUM(V.VoteTypeId = 2) AS UpVotes,
        SUM(V.VoteTypeId = 3) AS DownVotes
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId AND V.UserId = U.Id
    WHERE 
        U.Reputation > 1000 AND 
        U.CreationDate < NOW() - INTERVAL '1 year'
    GROUP BY 
        U.Id
), 
TypeCount AS (
    SELECT 
        U.UserId,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM 
        UserActivity U
    LEFT JOIN 
        Posts P ON U.UserId = P.OwnerUserId
    GROUP BY 
        U.UserId
)
SELECT 
    UA.DisplayName,
    UA.Reputation,
    UA.PostCount,
    UA.CommentCount,
    UA.UpVotes,
    UA.DownVotes,
    TC.QuestionCount,
    TC.AnswerCount
FROM 
    UserActivity UA
JOIN 
    TypeCount TC ON UA.UserId = TC.UserId
ORDER BY 
    UA.Reputation DESC, 
    UA.PostCount DESC 
LIMIT 10;
