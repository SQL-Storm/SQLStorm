-- {"query": "32014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 257} 

SELECT
    U.DisplayName,
    U.Reputation,
    SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    COUNT(DISTINCT P.Id) AS QuestionCount,
    COUNT(DISTINCT A.Id) AS AnswerCount,
    AVG(P.Score) AS AvgQuestionScore,
    AVG(A.Score) AS AvgAnswerScore
FROM
    Users U
LEFT JOIN
    Posts P ON U.Id = P.OwnerUserId AND P.PostTypeId = 1
LEFT JOIN
    Posts A ON U.Id = A.OwnerUserId AND A.PostTypeId = 2
LEFT JOIN
    Votes V ON (P.Id = V.PostId OR A.Id = V.PostId) AND V.VoteTypeId IN (2, 3)
WHERE
    U.Reputation > 1000
GROUP BY
    U.DisplayName, U.Reputation
HAVING
    COUNT(DISTINCT P.Id) > 0
ORDER BY
    AvgQuestionScore DESC, AvgAnswerScore DESC, UpVotes DESC, DownVotes ASC;
