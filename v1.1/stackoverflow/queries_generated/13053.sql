-- {"query": "13053.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 691} 

WITH UserActivity AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionsPosted,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswersPosted,
        COALESCE(SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END), 0) AS AcceptedAnswers,
        DENSE_RANK() OVER (ORDER BY COALESCE(SUM(P.Score), 0) DESC) AS ReputationRank
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    WHERE 
        P.CreationDate >= NOW() - INTERVAL '1 YEAR'
    GROUP BY 
        U.Id, U.DisplayName
),
CommentMetrics AS (
    SELECT
        P.Id AS PostId,
        COUNT(C.Id) AS TotalComments,
        SUM(C.Score) AS CommentScoreSum,
        MAX(C.CreationDate) AS LastCommentDate
    FROM 
        Posts P
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    WHERE
        P.CreationDate >= NOW() - INTERVAL '6 MONTHS'
    GROUP BY 
        P.Id
),
TagAnalysis AS (
    SELECT
        T.TagName,
        COUNT(DISTINCT P.Id) AS PostsWithTag,
        AVG(P.Score) AS AvgScore
    FROM
        Tags T
    INNER JOIN
        Posts P ON POSITION(CONCAT('<', T.TagName, '>') IN P.Tags) > 0
    GROUP BY
        T.TagName
    HAVING
        COUNT(DISTINCT P.Id) > 5
)
SELECT
    UA.UserId,
    UA.DisplayName,
    UA.QuestionsPosted,
    UA.AnswersPosted,
    UA.AcceptedAnswers,
    CM.TotalComments,
    CM.CommentScoreSum,
    CM.LastCommentDate,
    STRING_AGG(TA.TagName, ', ') AS ActiveTags
FROM
    UserActivity UA
LEFT JOIN
    Posts P ON UA.UserId = P.OwnerUserId
LEFT JOIN
    CommentMetrics CM ON P.Id = CM.PostId
LEFT JOIN
    Tags T ON POSITION(CONCAT('<', T.TagName, '>') IN P.Tags) > 0
LEFT JOIN
    TagAnalysis TA ON T.TagName = TA.TagName
WHERE
    UA.ReputationRank <= 100
GROUP BY
    UA.UserId, UA.DisplayName, UA.QuestionsPosted, UA.AnswersPosted, UA.AcceptedAnswers, CM.TotalComments, CM.CommentScoreSum, CM.LastCommentDate
ORDER BY
    UA.ReputationRank ASC, TotalComments DESC
LIMIT 50;
