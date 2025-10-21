-- {"query": "2092.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 417} 

WITH RecentUsers AS (
    SELECT Id AS UserId, DisplayName, Reputation, ROW_NUMBER() OVER (ORDER BY CreationDate DESC) AS RowNum
    FROM Users
    WHERE EmailHash IS NOT NULL
),
TopQuestions AS (
    SELECT P.Id AS QuestionId, P.Title, COUNT(PL.Id) AS LinkCount
    FROM Posts P
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId AND PL.LinkTypeId = 1
    WHERE P.PostTypeId = 1
    GROUP BY P.Id, P.Title
    HAVING COUNT(PL.Id) > 0
),
ActivePosters AS (
    SELECT U.Id AS UserId, U.DisplayName, COUNT(DISTINCT P.Id) AS PostCount
    FROM Users U
    JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE P.CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY U.Id, U.DisplayName
    HAVING COUNT(DISTINCT P.Id) > 5
),
AwardedBadges AS (
    SELECT B.UserId, STRING_AGG(B.Name, ', ') AS BadgeNames
    FROM Badges B
    WHERE B.Class IN (1, 2)
    GROUP BY B.UserId
)
SELECT 
    R.DisplayName AS RecentUserName,
    R.Reputation AS UserReputation,
    T.Title AS TopQuestionTitle,
    A.DisplayName AS ActiveUserName,
    A.PostCount AS PostsLastYear,
    COALESCE(AB.BadgeNames, 'No badges') AS Badges
FROM 
    RecentUsers R
    LEFT JOIN TopQuestions T ON T.QuestionId = R.UserId
    FULL OUTER JOIN ActivePosters A ON A.UserId = R.UserId
    LEFT JOIN AwardedBadges AB ON AB.UserId = R.UserId
WHERE 
    R.RowNum <= 10
ORDER BY 
    R.Reputation DESC, A.PostCount DESC NULLS LAST;
