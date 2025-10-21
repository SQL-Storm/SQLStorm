-- {"query": "26094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 634} 
WITH 
  -- Calculate the average reputation of users who have answered a question
  avg_reputation AS (
    SELECT AVG(U.Reputation) AS avg_rep
    FROM Users U
    JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE P.PostTypeId = 2
  ),
  
  -- Get the top 10 tags with the most questions
  top_tags AS (
    SELECT T.TagName, COUNT(*) AS num_questions
    FROM Tags T
    JOIN Posts P ON T.Id = (SELECT Id FROM Tags WHERE TagName = ANY(string_to_array(P.Tags, '><')))
    WHERE P.PostTypeId = 1
    GROUP BY T.TagName
    ORDER BY num_questions DESC
    LIMIT 10
  ),
  
  -- Calculate the number of upvotes and downvotes for each post
  post_votes AS (
    SELECT P.Id, SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes, SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes
    FROM Posts P
    JOIN Votes V ON P.Id = V.PostId
    GROUP BY P.Id
  ),
  
  -- Get the users who have answered the most questions
  top_answerers AS (
    SELECT U.Id, U.DisplayName, COUNT(*) AS num_answers
    FROM Users U
    JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE P.PostTypeId = 2
    GROUP BY U.Id, U.DisplayName
    ORDER BY num_answers DESC
    LIMIT 10
  )

SELECT 
  P.Id, 
  P.Title, 
  P.Score, 
  P.ViewCount, 
  P.AnswerCount, 
  PV.upvotes, 
  PV.downvotes, 
  U.DisplayName AS owner_name, 
  U.Reputation AS owner_reputation, 
  CASE 
    WHEN P.AcceptedAnswerId IS NOT NULL THEN 'Yes' 
    ELSE 'No' 
  END AS has_accepted_answer,
  CASE 
    WHEN P.ClosedDate IS NOT NULL THEN 'Yes' 
    ELSE 'No' 
  END AS is_closed,
  TT.TagName AS top_tag,
  TA.DisplayName AS top_answerer,
  AR.avg_rep AS avg_reputation
FROM 
  Posts P
  LEFT JOIN post_votes PV ON P.Id = PV.Id
  LEFT JOIN Users U ON P.OwnerUserId = U.Id
  LEFT JOIN top_tags TT ON TT.num_questions = (SELECT MAX(num_questions) FROM top_tags)
  LEFT JOIN top_answerers TA ON TA.num_answers = (SELECT MAX(num_answers) FROM top_answerers)
  CROSS JOIN avg_reputation AR
WHERE 
  P.PostTypeId = 1
  AND P.Score > 10
  AND P.ViewCount > 1000
  AND PV.upvotes > PV.downvotes
  AND U.Reputation > (SELECT avg_rep FROM avg_reputation)
ORDER BY 
  P.Score DESC, 
  P.ViewCount DESC;