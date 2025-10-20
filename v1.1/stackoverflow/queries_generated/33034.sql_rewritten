-- {"query": "33034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 395} 
SELECT 
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    COUNT(DISTINCT P.Id) AS QuestionCount,
    COUNT(DISTINCT A.Id) AS AnswerCount,
    AVG(P.Score) FILTER (WHERE P.PostTypeId = 1) AS AvgQuestionScore,
    AVG(A.Score) FILTER (WHERE A.PostTypeId = 2) AS AvgAnswerScore,
    SUM(CASE WHEN V1.VoteTypeId IN (2) THEN 1 ELSE 0 END) AS TotalUpVotes,
    SUM(CASE WHEN V1.VoteTypeId IN (3) THEN 1 ELSE 0 END) AS TotalDownVotes,
    COUNT(DISTINCT B.Id) AS BadgeCount,
    COUNT(DISTINCT C.Id) AS CommentCount,
    COUNT(DISTINCT R.RelatedPostId) AS LinkedPostsCount
FROM 
    Users U
LEFT JOIN 
    Posts P ON U.Id = P.OwnerUserId AND P.PostTypeId = 1
LEFT JOIN 
    Posts A ON U.Id = A.OwnerUserId AND A.PostTypeId = 2
LEFT JOIN 
    Posts P2 ON U.Id = P2.OwnerUserId AND P2.PostTypeId = 1
LEFT JOIN 
    Votes V1 ON V1.UserId = U.Id AND V1.PostId IN (P.Id, A.Id)
LEFT JOIN 
    Badges B ON B.UserId = U.Id
LEFT JOIN 
    Comments C ON C.UserId = U.Id
LEFT JOIN 
    PostLinks R ON R.PostId IN (P.Id, A.Id) OR R.RelatedPostId IN (P.Id, A.Id)
WHERE 
    U.CreationDate >= cast('2024-10-01' as date) - INTERVAL '1 year'
GROUP BY 
    U.Id, U.DisplayName, U.Reputation
ORDER BY 
    U.Reputation DESC
LIMIT 100;