-- {"query": "43058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 324} 
SELECT
    U.Id AS UserId,
    U.DisplayName,
    COUNT(DISTINCT P.Id) AS TotalPosts,
    SUM(CASE WHEN P.Score > 10 THEN 1 ELSE 0 END) AS HighScorePosts,
    AVG(P.ViewCount) AS AvgViewCount,
    MAX(B.Date) AS LastBadgeDate,
    COUNT(DISTINCT C.Id) AS TotalComments,
    (SELECT COUNT(*) FROM Badges WHERE UserId = U.Id AND Class = 1) AS GoldBadges,
    DENSE_RANK() OVER (ORDER BY (COUNT(DISTINCT P.Id) + SUM(CASE WHEN P.Score > 10 THEN 1 ELSE 0 END)) DESC) AS UserRank
FROM
    Users U
LEFT JOIN
    Posts P ON U.Id = P.OwnerUserId
LEFT JOIN
    Badges B ON U.Id = B.UserId
LEFT JOIN
    Comments C ON U.Id = C.UserId
WHERE
    U.CreationDate >= '2020-01-01' AND U.LastAccessDate < '2023-01-01'
GROUP BY
    U.Id, U.DisplayName
HAVING
    COUNT(DISTINCT P.Id) > 10
ORDER BY
    TotalPosts DESC, HighScorePosts DESC, AvgViewCount DESC
LIMIT 100;