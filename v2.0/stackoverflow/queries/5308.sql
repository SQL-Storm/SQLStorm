-- {"query": "5308.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 684}
SELECT
  U.DisplayName AS UserName,
  U.Reputation,
  U.CreationDate AS UserCreation,
  P.Id AS PostId,
  P.Title,
  P.PostTypeId,
  P.CreationDate AS PostCreation,
  P.ViewCount,
  P.Score,
  P.Tags,
  P.OwnerUserId,
  COUNT(DISTINCT A.Id) AS AnswerCount,
  AVG(V2.BountyAmount) AS AvgBountyForPost,
  COUNT(C.Id) AS CommentCount,
  MAX(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS HasUpvote,
  MAX(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS HasDownvote,
  SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteSum,
  SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteSum,
  ROW_NUMBER() OVER (
    PARTITION BY P.OwnerUserId
    ORDER BY P.CreationDate DESC
  ) AS UserPostRank,
  STRING_AGG(T.TagName, ',') AS AllTags,
  CASE
    WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
    ELSE 'Open'
  END AS PostStatus,
  (SELECT COUNT(*) FROM PostLinks PL WHERE PL.PostId = P.Id) AS LinkCount,
  (SELECT COUNT(*) FROM PostLinks PL WHERE PL.RelatedPostId = P.Id) AS ReferencedByCount,
  (SELECT PL.LinkTypeId
     FROM PostLinks PL
     WHERE PL.PostId = P.Id
     ORDER BY PL.CreationDate DESC
     LIMIT 1) AS LastLinkType,
  (SELECT MAX(PH.CreationDate) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId = 10) AS LastCloseVoteDate
FROM
  Posts P
LEFT JOIN Users U ON P.OwnerUserId = U.Id
LEFT JOIN Votes V ON V.PostId = P.Id
LEFT JOIN Votes V2 ON V2.PostId = P.Id
LEFT JOIN Comments C ON C.PostId = P.Id
LEFT JOIN Posts A ON A.ParentId = P.Id
LEFT JOIN Tags T ON T.WikiPostId = P.Id OR T.ExcerptPostId = P.Id
WHERE
  P.PostTypeId IN (1, 2)
  AND P.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '2 years') + (TIMESTAMP '2024-10-01 12:34:56' - DATE_TRUNC('day', TIMESTAMP '2024-10-01 12:34:56'))
  AND (P.Body LIKE '%benchmark%' OR P.Title LIKE '%benchmark%')
GROUP BY
  U.DisplayName,
  U.Reputation,
  U.CreationDate,
  P.Id,
  P.Title,
  P.PostTypeId,
  P.CreationDate,
  P.ViewCount,
  P.Score,
  P.Tags,
  P.OwnerUserId,
  P.ClosedDate,
  P.LastEditDate,
  P.OwnerUserId
ORDER BY
  UserName,
  P.CreationDate DESC
LIMIT 100;