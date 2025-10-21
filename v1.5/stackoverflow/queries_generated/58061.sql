-- {"query": "58061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 2147} 

SELECT 
    U.Id AS UserId,
    U.DisplayName,
    COUNT(DISTINCT P.Id) AS QuestionCount,
    COUNT(DISTINCT C.Id) AS CommentCount,
    COUNT(DISTINCT V.Id) AS UpVotesGiven,
    COUNT(DISTINCT B.Id) AS GoldBadges,
    AVG(P.AnswerCount) AS AvgAnswersPerQuestion,
    (SELECT AVG(AnswerCount) FROM Posts WHERE OwnerUserId = U.Id AND PostTypeId = 1) AS GlobalAvgAnswers,
    SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 11) THEN 1 ELSE 0 END) AS CloseReopenEvents,
    (SELECT COUNT(*) FROM Posts AS P2 WHERE P2.OwnerUserId = U.Id AND P2.PostTypeId = 1 AND EXISTS (SELECT 1 FROM Votes WHERE PostId = P2.Id AND VoteTypeId = 2)) AS QuestionsWithUpvotes,
    AVG(ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'), 1)) AS AvgTagsPerQuestion,
    RANK() OVER (PARTITION BY CASE WHEN U.Reputation BETWEEN 1000 AND 5000 THEN '1k-5k' WHEN U.Reputation > 5000 THEN '5k+' END ORDER BY COUNT(DISTINCT P.Id) DESC) AS ReputationRank
FROM 
    Users U
LEFT JOIN Posts P ON U.Id = P.OwnerUserId AND P.PostTypeId = 1 AND P.CreationDate BETWEEN '2010-01-01' AND '2020-12-31'
LEFT JOIN Comments C ON U.Id = C.UserId
LEFT JOIN Votes V ON U.Id = V.UserId AND V.VoteTypeId = 2
LEFT JOIN Badges B ON U.Id = B.UserId AND B.Class = 1 AND B.TagBased = 0
LEFT JOIN PostHistory PH ON P.Id = PH.PostId AND PH.PostHistoryTypeId IN (10, 11)
WHERE 
    U.Reputation > 1000
GROUP BY 
    U.Id, U.DisplayName, U.Reputation
HAVING 
    COUNT(DISTINCT P.Id) > 10
    AND AVG(P.AnswerCount) > (SELECT AVG(AnswerCount) FROM Posts WHERE PostTypeId = 1)
ORDER BY 
    GoldBadges DESC, QuestionCount DESC, ReputationRank
LIMIT 100;
