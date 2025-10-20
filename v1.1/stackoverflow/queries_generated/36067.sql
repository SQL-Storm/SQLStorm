-- {"query": "36067.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 460} 
SELECT
  P.Id AS PostId,
  P.Title,
  P.PostTypeId,
  P.CreationDate,
  P.ViewCount,
  P.Score,
  P.OwnerUserId,
  U.DisplayName AS OwnerDisplayName,
  U.Reputation,
  P.LastActivityDate,
  P.Tags,
  COUNT(C.Id) AS CommentCount,
  COUNT(V.Id) AS VoteCount,
  SUM(CASE WHEN VT.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
  SUM(CASE WHEN VT.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
  SUM(CASE WHEN VT.Name = 'Favorite' THEN 1 ELSE 0 END) AS Favorites,
  SUM(CASE WHEN VT.Name = 'AcceptedByOriginator' THEN 1 ELSE 0 END) AS AcceptedVotes,
  ARRAY_AGG(DISTINCT TL.Name) FILTER (WHERE L.Id IS NOT NULL) AS LinkTypesUsed,
  JSON_BUILD_OBJECT(
    'TopTags', (SELECT string_agg(t.TagName, ',') FROM Tags t WHERE t.Id = P.Tags::int[][1] OR t.WikiPostId = P.Id),
    'Histories', (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = P.Id)
  ) AS Meta
FROM Posts P
LEFT JOIN Users U ON P.OwnerUserId = U.Id
LEFT JOIN Comments C ON C.PostId = P.Id
LEFT JOIN Votes V ON V.PostId = P.Id
LEFT JOIN VoteTypes VT ON V.VoteTypeId = VT.Id
LEFT JOIN PostLinks L ON L.PostId = P.Id
LEFT JOIN LinkTypes TL ON L.LinkTypeId = TL.Id
WHERE P.Id IN (
  SELECT Id FROM Posts
  WHERE PostTypeId IN (1,2) -- questions and answers
)
GROUP BY
  P.Id, P.Title, P.PostTypeId, P.CreationDate, P.ViewCount, P.Score,
  P.OwnerUserId, U.DisplayName, U.Reputation, P.LastActivityDate, P.Tags, P.Title
ORDER BY
  P.CreationDate DESC
LIMIT 100;