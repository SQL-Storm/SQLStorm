-- {"query": "13005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 673} 

WITH UserActivity AS (
    SELECT 
        U.Id AS UserId,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE 0 END) AS QuestionScore,
        SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE 0 END) AS AnswerScore,
        ROW_NUMBER() OVER (ORDER BY SUM(P.Score) DESC NULLS LAST) AS ScoreRank
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    WHERE 
        U.Reputation > 1000
        AND P.CreationDate > '2022-01-01'
    GROUP BY 
        U.Id
),
PostMetrics AS (
    SELECT 
        P.Id AS PostId,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        COALESCE(STRING_AGG(DISTINCT T.TagName, ', '), 'No Tags') AS TagList,
        LAG(P.Score, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousScore
    FROM 
        Posts P
    LEFT JOIN 
        Tags T ON P.Tags LIKE CONCAT('%<', T.TagName, '>%')
    WHERE 
        P.PostTypeId IN (1, 2)
),
CommentSummary AS (
    SELECT 
        P.Id AS PostId,
        COUNT(C.Id) AS CommentCount,
        MAX(C.Score) AS MaxCommentScore
    FROM 
        Posts P
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    GROUP BY 
        P.Id
)
SELECT 
    UA.UserId,
    UA.TotalPosts,
    UA.TotalBadges,
    PM.PostId,
    PM.PostTypeId,
    PM.Score,
    PM.PreviousScore,
    PM.ViewCount,
    PM.TagList,
    CS.CommentCount,
    CS.MaxCommentScore,
    (SELECT AVG(PH.Score) FROM PostHistory PH WHERE PH.UserId = UA.UserId AND PH.PostHistoryTypeId = 5) AS AvgEditScore
FROM 
    UserActivity UA
JOIN 
    PostMetrics PM ON UA.UserId = PM.OwnerUserId
LEFT JOIN 
    CommentSummary CS ON PM.PostId = CS.PostId
WHERE 
    UA.ScoreRank <= 100
    AND PM.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = PM.PostTypeId)
ORDER BY 
    UA.ScoreRank, PM.Score DESC;
