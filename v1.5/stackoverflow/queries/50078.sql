-- {"query": "50078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 860} 
WITH TagPerformance AS (
    SELECT
        T.TagName,
        P.OwnerUserId AS UserId,
        SUM(P.Score) AS TotalScore,
        COUNT(P.Id) AS PostCount,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(P.FavoriteCount) FILTER (WHERE P.PostTypeId = 1) AS TotalFavoriteCount
    FROM Posts AS P
    JOIN Tags AS T ON P.Tags LIKE '%' || '<' || T.TagName || '>' || '%'
    WHERE P.OwnerUserId IS NOT NULL
      AND P.CreationDate > (SELECT cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 year')
    GROUP BY T.TagName, P.OwnerUserId
),
UserRanking AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        TP.TagName,
        TP.TotalScore,
        TP.AnswerCount,
        TP.QuestionCount,
        ROW_NUMBER() OVER(PARTITION BY TP.TagName ORDER BY TP.TotalScore DESC, U.Reputation DESC) as RankInTag,
        (SELECT COUNT(*) FROM Badges B WHERE B.UserId = U.Id AND B.Name = TP.TagName AND B.TagBased = '1') AS TagSpecificBadges
    FROM Users AS U
    JOIN TagPerformance AS TP ON U.Id = TP.UserId
    WHERE U.Reputation > 1000 AND TP.AnswerCount > 5
),
AnswerAcceptanceRate AS (
    SELECT
        A.OwnerUserId,
        CAST(SUM(CASE WHEN Q.AcceptedAnswerId = A.Id THEN 1 ELSE 0 END) AS REAL) * 100 / COUNT(A.Id) AS AcceptanceRate
    FROM Posts A
    JOIN Posts Q ON A.ParentId = Q.Id
    WHERE A.PostTypeId = 2 AND A.OwnerUserId IN (SELECT UserId FROM UserRanking WHERE RankInTag <= 10)
    GROUP BY A.OwnerUserId
    HAVING COUNT(A.Id) > 10
),
CommentAnalysis AS (
    SELECT
        C.UserId,
        AVG(C.Score) as AvgCommentScore,
        COUNT(C.Id) as TotalComments
    FROM Comments C
    WHERE C.UserId IN (SELECT UserId FROM UserRanking WHERE RankInTag <= 10)
    GROUP BY C.UserId
)
SELECT
    UR.TagName,
    UR.RankInTag,
    UR.DisplayName,
    UR.Reputation,
    UR.TotalScore,
    UR.AnswerCount,
    UR.QuestionCount,
    UR.TagSpecificBadges,
    COALESCE(AAR.AcceptanceRate, 0) AS AcceptanceRate,
    COALESCE(CA.AvgCommentScore, 0) AS AvgCommentScore,
    (SELECT STRING_AGG(B.Name, ', ' ORDER BY B.Class, B.Date DESC)
     FROM (
         SELECT Name, Class, Date,
         ROW_NUMBER() OVER(PARTITION BY Class ORDER BY Date DESC) as rn
         FROM Badges WHERE UserId = UR.UserId AND TagBased = '0'
     ) B
     WHERE B.rn <= 3
    ) AS Top3NonTagBadges
FROM UserRanking UR
LEFT JOIN AnswerAcceptanceRate AAR ON UR.UserId = AAR.OwnerUserId
LEFT JOIN CommentAnalysis CA ON UR.UserId = CA.UserId
WHERE UR.RankInTag <= 10
  AND UR.TagName IN (SELECT TagName FROM Tags ORDER BY Count DESC LIMIT 20)
ORDER BY UR.TagName, UR.RankInTag;