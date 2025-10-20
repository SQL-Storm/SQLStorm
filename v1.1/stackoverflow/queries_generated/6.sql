-- {"query": "6.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 146} 
WITH RecursiveCTE AS (
    SELECT P1.Id AS OriginalPostId, P2.Id AS RelatedPostId, 0 AS Level
    FROM Posts P1
    JOIN PostLinks PL ON P1.Id = PL.PostId
    JOIN Posts P2 ON PL.RelatedPostId = P2.Id
    WHERE PL.LinkTypeId = 1
    UNION ALL
    SELECT RC.OriginalPostId, P.Id, Level + 1
    FROM RecursiveCTE RC
    JOIN PostLinks PL ON RC.RelatedPostId = PL.PostId
    JOIN Posts P ON PL.RelatedPostId = P.Id
    WHERE Level < 3
)
SELECT *
FROM RecursiveCTE;