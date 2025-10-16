-- {"query": "26021.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 420} 

WITH TopUsers AS (
  SELECT 
    U.Id, 
    U.DisplayName, 
    SUM(P.Score) AS TotalScore
  FROM 
    Users U
  JOIN 
    Posts P ON U.Id = P.OwnerUserId
  WHERE 
    P.PostTypeId = 2
  GROUP BY 
    U.Id, 
    U.DisplayName
  ORDER BY 
    TotalScore DESC
  LIMIT 10
),
TopTags AS (
  SELECT 
    T.TagName, 
    COUNT(DISTINCT P.Id) AS PostCount
  FROM 
    Posts P
  JOIN 
    Tags T ON P.Tags LIKE '%' + T.TagName + '%'
  GROUP BY 
    T.TagName
  ORDER BY 
    PostCount DESC
  LIMIT 5
),
QuestionHistory AS (
  SELECT 
    P.Id, 
    PH.PostHistoryTypeId, 
    PH.CreationDate, 
    PH.UserId
  FROM 
    Posts P
  JOIN 
    PostHistory PH ON P.Id = PH.PostId
  WHERE 
    P.PostTypeId = 1 AND PH.PostHistoryTypeId IN (10, 11)
)
SELECT 
  U.DisplayName, 
  U.Reputation, 
  P.Title, 
  P.Score, 
  P.ViewCount, 
  P.AnswerCount, 
  T.TagName, 
  TU.TotalScore, 
  QH.PostHistoryTypeId, 
  QH.CreationDate
FROM 
  Users U
JOIN 
  Posts P ON U.Id = P.OwnerUserId
JOIN 
  PostLinks PL ON P.Id = PL.PostId
JOIN 
  Tags T ON P.Tags LIKE '%' + T.TagName + '%'
JOIN 
  TopUsers TU ON U.Id = TU.Id
LEFT JOIN 
  QuestionHistory QH ON P.Id = QH.Id
WHERE 
  P.PostTypeId = 1 AND T.TagName IN (SELECT TagName FROM TopTags)
ORDER BY 
  P.Score DESC, 
  P.ViewCount DESC;
