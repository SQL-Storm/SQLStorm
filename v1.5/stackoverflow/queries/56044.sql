WITH TopUsers AS (
  SELECT 
    U.Id, 
    U.DisplayName, 
    COUNT(P.Id) AS PostCount, 
    SUM(P.Score) AS TotalScore
  FROM 
    Users U
  JOIN 
    Posts P ON U.Id = P.OwnerUserId
  WHERE 
    P.PostTypeId = 1 AND P.Score > 0
  GROUP BY 
    U.Id, U.DisplayName
  HAVING 
    COUNT(P.Id) > 10 AND SUM(P.Score) > 100
),
TopTags AS (
  SELECT 
    T.TagName, 
    COUNT(P.Id) AS PostCount, 
    SUM(P.Score) AS TotalScore
  FROM 
    Posts P
  JOIN 
    Tags T ON POSITION(T.TagName IN P.Tags) > 0
  WHERE 
    P.PostTypeId = 1 AND P.Score > 0
  GROUP BY 
    T.TagName
  HAVING 
    COUNT(P.Id) > 5 AND SUM(P.Score) > 50
)
SELECT 
  TU.DisplayName, 
  TT.TagName, 
  P.Score, 
  P.Title, 
  P.Body
FROM 
  Posts P
JOIN 
  TopUsers TU ON P.OwnerUserId = TU.Id
JOIN 
  TopTags TT ON POSITION(TT.TagName IN P.Tags) > 0
WHERE 
  P.PostTypeId = 1 AND P.Score > 0
ORDER BY 
  P.Score DESC, 
  P.CreationDate DESC
LIMIT 100;