SELECT 
    P.Id AS PostId,
    P.Title,
    P.CreationDate,
    U.DisplayName AS OwnerDisplayName,
    P.Score,
    P.ViewCount,
    T.TagName
FROM 
    Posts P
JOIN 
    Users U ON P.OwnerUserId = U.Id
JOIN 
    Tags T ON P.Tags LIKE '%' || T.TagName || '%'
WHERE 
    P.PostTypeId = 1  -- Only questions
ORDER BY 
    P.CreationDate DESC
LIMIT 10;
