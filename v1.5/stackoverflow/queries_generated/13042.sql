-- {"query": "13042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 656} 

WITH UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        MAX(U.Reputation) AS Reputation,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT P.Id) DESC, MAX(U.Reputation) DESC) AS Rank
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    WHERE 
        P.CreationDate BETWEEN NOW() - INTERVAL '1 YEAR' AND NOW()
    GROUP BY 
        U.Id, U.DisplayName
),
RecentQuestions AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        PH.CreationDate AS LastEditDate,
        COALESCE(U.DisplayName, 'Anonymous') AS LastEditorDisplayName
    FROM 
        Posts P
    LEFT JOIN 
        (SELECT PostId, MAX(CreationDate) AS CreationDate FROM PostHistory WHERE PostHistoryTypeId IN (4, 5, 6) GROUP BY PostId) PH 
        ON P.Id = PH.PostId
    LEFT JOIN 
        Users U ON PH.UserId = U.Id
    WHERE 
        P.PostTypeId = 1 
        AND P.CreationDate BETWEEN NOW() - INTERVAL '1 MONTH' AND NOW()
),
TopAnswers AS (
    SELECT 
        P.Id,
        P.ParentId AS QuestionId,
        P.Score,
        ROW_NUMBER() OVER (PARTITION BY P.ParentId ORDER BY P.Score DESC) AS AnswerRank
    FROM 
        Posts P
    WHERE 
        P.PostTypeId = 2
)
SELECT 
    UA.DisplayName,
    UA.TotalPosts,
    UA.QuestionsAsked,
    UA.AnswersProvided,
    UA.Reputation,
    RQ.Title AS MostRecentQuestionTitle,
    RQ.Score AS MostRecentQuestionScore,
    RQ.ViewCount AS MostRecentQuestionViewCount,
    TA.Score AS TopAnswerScore
FROM 
    UserActivity UA
LEFT JOIN 
    RecentQuestions RQ ON UA.Id = RQ.Id
LEFT JOIN 
    TopAnswers TA ON RQ.Id = TA.QuestionId AND TA.AnswerRank = 1
WHERE 
    UA.Rank <= 10
    AND RQ.AnswerCount > 0
ORDER BY 
    UA.Rank, RQ.Score DESC;
