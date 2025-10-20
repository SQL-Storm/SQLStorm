-- {"query": "56099.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 354} 

WITH Top10Tags AS (
  SELECT 
    T.TagName, 
    COUNT(DISTINCT P.Id) AS PostCount
  FROM 
    Tags T
  JOIN 
    Posts P ON P.Tags LIKE CONCAT('%', T.TagName, '%')
  GROUP BY 
    T.TagName
  ORDER BY 
    PostCount DESC
  LIMIT 10
),
Top10UsersByReputation AS (
  SELECT 
    U.Id, 
    U.DisplayName, 
    U.Reputation
  FROM 
    Users U
  ORDER BY 
    U.Reputation DESC
  LIMIT 10
),
QuestionAnswers AS (
  SELECT 
    P.Id, 
    P.Title, 
    P.Score, 
    P.ViewCount, 
    COUNT(A.Id) AS AnswerCount
  FROM 
    Posts P
  LEFT JOIN 
    Posts A ON A.ParentId = P.Id
  WHERE 
    P.PostTypeId = 1
  GROUP BY 
    P.Id, P.Title, P.Score, P.ViewCount
)
SELECT 
  T.TagName, 
  TU.DisplayName, 
  QA.Title, 
  QA.Score, 
  QA.ViewCount, 
  QA.AnswerCount
FROM 
  Top10Tags T
JOIN 
  Posts P ON P.Tags LIKE CONCAT('%', T.TagName, '%')
JOIN 
  QuestionAnswers QA ON QA.Id = P.Id
JOIN 
  Top10UsersByReputation TU ON TU.Id = P.OwnerUserId
WHERE 
  P.PostTypeId = 1 AND P.Score > 10 AND P.ViewCount > 1000
ORDER BY 
  T.PostCount DESC, TU.Reputation DESC, QA.Score DESC;
