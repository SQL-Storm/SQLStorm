-- {"query": "56049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 513} 
WITH TopPosts AS (
  SELECT 
    P.Id, 
    P.Title, 
    P.Score, 
    P.ViewCount, 
    P.AnswerCount, 
    P.CommentCount, 
    P.FavoriteCount, 
    P.ClosedDate, 
    U.DisplayName AS OwnerDisplayName, 
    U.Reputation AS OwnerReputation
  FROM 
    Posts P
  JOIN 
    Users U ON P.OwnerUserId = U.Id
  WHERE 
    P.PostTypeId = 1 AND P.Score > 0
),
TopTags AS (
  SELECT 
    T.Id, 
    T.TagName, 
    T.Count, 
    T.ExcerptPostId, 
    T.WikiPostId
  FROM 
    Tags T
  WHERE 
    T.Count > 100
),
PostTagLinks AS (
  SELECT 
    P.Id AS PostId, 
    T.Id AS TagId, 
    P.Title, 
    P.Score, 
    T.TagName
  FROM 
    Posts P
  JOIN 
    PostLinks PL ON P.Id = PL.PostId
  JOIN 
    Tags T ON PL.RelatedPostId = T.WikiPostId
  WHERE 
    PL.LinkTypeId = 1 AND P.PostTypeId = 1
)
SELECT 
  TP.Id, 
  TP.Title, 
  TP.Score, 
  TP.ViewCount, 
  TP.AnswerCount, 
  TP.CommentCount, 
  TP.FavoriteCount, 
  TP.ClosedDate, 
  TP.OwnerDisplayName, 
  TP.OwnerReputation, 
  TT.TagName, 
  PTL.TagId, 
  COUNT(DISTINCT V.Id) AS VoteCount
FROM 
  TopPosts TP
JOIN 
  PostTagLinks PTL ON TP.Id = PTL.PostId
JOIN 
  Tags TT ON PTL.TagId = TT.Id
JOIN 
  Votes V ON TP.Id = V.PostId
WHERE 
  V.VoteTypeId IN (2, 3) AND TP.Score > 0
GROUP BY 
  TP.Id, 
  TP.Title, 
  TP.Score, 
  TP.ViewCount, 
  TP.AnswerCount, 
  TP.CommentCount, 
  TP.FavoriteCount, 
  TP.ClosedDate, 
  TP.OwnerDisplayName, 
  TP.OwnerReputation, 
  TT.TagName, 
  PTL.TagId
ORDER BY 
  VoteCount DESC;