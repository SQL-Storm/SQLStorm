-- {"query": "52079.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 320} 
SELECT
    T.TagName,
    COUNT(DISTINCT P.Id) AS NumQuestions,
    AVG(P.Score) AS AvgScore,
    SUM(P.ViewCount) AS TotalViews,
    COUNT(DISTINCT C.Id) AS NumComments,
    COUNT(DISTINCT V.Id) AS NumVotes,
    (
        SELECT U.DisplayName
        FROM Users U
        WHERE U.Id = (
            SELECT PH.UserId
            FROM PostHistory PH
            WHERE PH.PostId = P.Id
            GROUP BY PH.UserId
            ORDER BY COUNT(*) DESC
            LIMIT 1
        )
    ) AS TopEditor,
    (
        SELECT STRING_AGG(B.Name, ', ') WITHIN GROUP (ORDER BY B.Date DESC)
        FROM Badges B
        WHERE B.UserId = U.Id AND B.Class = 1
        GROUP BY B.UserId
    ) AS GoldBadges
FROM
    Tags T
LEFT JOIN
    Posts P ON P.Tags LIKE CONCAT('%<', T.TagName, '>%') AND P.PostTypeId = 1
LEFT JOIN
    Comments C ON C.PostId = P.Id
LEFT JOIN
    Votes V ON V.PostId = P.Id
LEFT JOIN
    Users U ON U.Id = P.OwnerUserId
WHERE
    T.Count > 100
GROUP BY
    T.Id, T.TagName, U.Id
HAVING
    COUNT(DISTINCT P.Id) > 0
ORDER BY
    NumQuestions DESC,
    AvgScore DESC
LIMIT 50;