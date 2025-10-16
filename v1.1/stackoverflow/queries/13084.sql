WITH UserActivity AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionsAsked,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswersProvided,
        MAX(U.LastAccessDate) AS LastActivity,
        ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) DESC) AS QuestionRank
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    WHERE 
        U.Reputation > 1000
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
),
TopEditors AS (
    SELECT 
        UserId,
        COUNT(*) AS EditCount
    FROM 
        PostHistory
    WHERE 
        PostHistoryTypeId IN (4, 5, 6)
    GROUP BY 
        UserId
    HAVING 
        COUNT(*) > 5
),
HighScorePosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        U.Id AS OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        DENSE_RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC) AS PostRank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND Score > 0)
)
SELECT 
    UA.UserId,
    UA.DisplayName,
    UA.QuestionsAsked,
    UA.AnswersProvided,
    UA.LastActivity,
    TE.EditCount,
    HSP.Id AS HighScorePostId,
    HSP.Title,
    HSP.Score
FROM 
    UserActivity UA
LEFT JOIN 
    TopEditors TE ON UA.UserId = TE.UserId
LEFT JOIN 
    HighScorePosts HSP ON UA.UserId = HSP.OwnerUserId AND HSP.PostRank = 1
WHERE 
    UA.QuestionRank <= 10
GROUP BY
    UA.UserId,
    UA.DisplayName,
    UA.QuestionsAsked,
    UA.AnswersProvided,
    UA.LastActivity,
    UA.QuestionRank,
    TE.EditCount,
    HSP.Id,
    HSP.Title,
    HSP.Score,
    HSP.PostRank
ORDER BY 
    UA.QuestionsAsked DESC, TE.EditCount DESC;