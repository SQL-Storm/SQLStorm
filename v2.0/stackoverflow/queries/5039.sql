-- {"query": "5039.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 500}
SELECT
    U.Id AS UserId,
    U.DisplayName AS UserName,
    U.Reputation,
    COUNT(DISTINCT P.Id) AS PostCount,
    SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCount,
    SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCount,
    AVG(P.Score) AS AvgPostScore,
    MAX(P.LastActivityDate) AS LastActive,
    (
        SELECT SUM(coalesce(P2.Score,0))
        FROM Posts P2
        WHERE P2.OwnerUserId = U.Id
          AND P2.OwnerUserId IS NOT NULL
          AND P2.OwnerUserId <= U.Id
    ) AS CumulativeScore,
    (
        SELECT COUNT(DISTINCT TRIM(T.TagName))
        FROM Posts Q
        JOIN Tags T ON Q.Tags LIKE '%' || '<' || T.TagName || '>' || '%'
        WHERE Q.OwnerUserId = U.Id
          AND Q.PostTypeId = 1
    ) AS UniqueQuestionTagsUsed,
    COALESCE(LINKS.LinkedCount, 0) AS LinkedPostsCount
FROM
    Users U
    LEFT JOIN Posts P ON P.OwnerUserId = U.Id
    LEFT JOIN (
        SELECT
            P.OwnerUserId,
            COUNT(*) AS LinkedCount
        FROM
            Posts P
            JOIN PostLinks PL ON PL.PostId = P.Id
        WHERE
            PL.LinkTypeId IN (1, 3)
        GROUP BY
            P.OwnerUserId
    ) LINKS ON LINKS.OwnerUserId = U.Id
WHERE
    U.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2' YEAR)
GROUP BY
    U.Id,
    U.DisplayName,
    U.Reputation,
    U.CreationDate,
    U.LastAccessDate,
    LINKS.LinkedCount
HAVING
    AVG(CASE WHEN P.PostTypeId IN (1,2) THEN P.Score ELSE NULL END) > 0
ORDER BY
    CumulativeScore DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;