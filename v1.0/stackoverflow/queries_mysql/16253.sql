
SELECT 
    P.Title,
    U.DisplayName AS OwnerDisplayName,
    P.CreationDate,
    P.Score,
    P.ViewCount,
    T.TagName
FROM 
    Posts P
JOIN 
    Users U ON P.OwnerUserId = U.Id
JOIN 
    Tags T ON T.ExcerptPostId = P.Id
WHERE 
    P.PostTypeId = 1
GROUP BY 
    P.Title, U.DisplayName, P.CreationDate, P.Score, P.ViewCount, T.TagName
ORDER BY 
    P.CreationDate DESC
LIMIT 10;
