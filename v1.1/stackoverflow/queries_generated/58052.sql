-- {"query": "58052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1682} 

WITH ActiveUsers AS (
    SELECT 
        U.Id, 
        U.DisplayName, 
        U.Reputation, 
        COUNT(DISTINCT P.Id) AS PostCount,
        COUNT(DISTINCT C.Id) AS CommentCount,
        COUNT(DISTINCT V.Id) AS VoteCount,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId AND P.PostTypeId = 1 AND P.CreationDate >= NOW() - INTERVAL '1 YEAR'
    LEFT JOIN Comments C ON U.Id = C.UserId AND C.CreationDate >= NOW() - INTERVAL '6 MONTHS'
    LEFT JOIN Votes V ON U.Id = V.UserId AND V.VoteTypeId IN (2,3,8) AND V.CreationDate >= NOW() - INTERVAL '3 MONTHS'
    LEFT JOIN Badges B ON U.Id = B.UserId AND B.Class = 1 AND B.Date >= NOW() - INTERVAL '2 YEARS'
    WHERE U.Reputation > 5000 AND U.DownVotes < (U.UpVotes * 0.1)
    GROUP BY U.Id
), PostMetrics AS (
    SELECT 
        OwnerUserId,
        AVG(Score) FILTER (WHERE PostTypeId = 1) AS AvgQuestionScore,
        MAX(ViewCount) AS MaxViews,
        SUM(AnswerCount) AS TotalAnswersGenerated,
        COUNT(DISTINCT CASE WHEN AcceptedAnswerId IS NOT NULL THEN Id END) AS AcceptedAnswers,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY Score) AS P90PostScore
    FROM Posts
    WHERE CreationDate >= NOW() - INTERVAL '5 YEARS'
    GROUP BY OwnerUserId
), TagEngagement AS (
    SELECT
        P.OwnerUserId,
        COUNT(DISTINCT T.Id) AS UniqueTagsUsed,
        MODE() WITHIN GROUP (ORDER BY SPLIT_PART(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><', 1)) AS MostFrequentTag
    FROM Posts P
    JOIN Tags T ON POSITION(T.TagName IN P.Tags) > 0
    WHERE P.PostTypeId = 1
    GROUP BY P.OwnerUserId
)
SELECT 
    AU.*,
    PM.AvgQuestionScore,
    PM.MaxViews,
    PM.TotalAnswersGenerated,
    PM.AcceptedAnswers,
    PM.P90PostScore,
    TE.UniqueTagsUsed,
    TE.MostFrequentTag,
    RANK() OVER (ORDER BY (AU.PostCount * 0.3 + AU.CommentCount * 0.2 + AU.VoteCount * 0.1 + AU.BadgeCount * 0.4) DESC) AS ActivityRank,
    DENSE_RANK() OVER (ORDER BY PM.P90PostScore DESC) AS QualityRank
FROM ActiveUsers AU
JOIN PostMetrics PM ON AU.Id = PM.OwnerUserId
JOIN TagEngagement TE ON AU.Id = TE.OwnerUserId
WHERE PM.TotalAnswersGenerated > 100 AND TE.UniqueTagsUsed >= 5
ORDER BY (AU.Reputation * 0.25 + PM.AvgQuestionScore * 0.35 + TE.UniqueTagsUsed * 0.15 + AU.BadgeCount * 0.25) DESC
LIMIT 100;
