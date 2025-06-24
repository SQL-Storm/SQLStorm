
WITH UserStats AS (
    SELECT 
        U.Id AS UserId,
        U.Reputation,
        COUNT(DISTINCT P.Id) AS PostCount,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Votes V ON P.Id = V.PostId
    GROUP BY U.Id, U.Reputation
),
TagStats AS (
    SELECT 
        T.Id AS TagId,
        T.TagName,
        COUNT(P.Id) AS PostCount,
        SUM(P.ViewCount) AS TotalViews,
        SUM(P.Score) AS TotalScore
    FROM Tags T
    LEFT JOIN Posts P ON P.Tags LIKE '%' + T.TagName + '%'
    GROUP BY T.Id, T.TagName
)
SELECT 
    U.UserId,
    U.Reputation,
    U.PostCount,
    U.QuestionCount,
    U.AnswerCount,
    U.UpvoteCount,
    U.DownvoteCount,
    T.TagId,
    T.TagName,
    T.PostCount AS TagPostCount,
    T.TotalViews,
    T.TotalScore
FROM UserStats U
JOIN TagStats T ON U.PostCount > 0  
ORDER BY U.Reputation DESC, T.TotalScore DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
