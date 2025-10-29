-- {"query": "4940.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1348} 

WITH RECURSIVE TagHierarchy AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    t.Id AS RootTagId,
    0 AS Depth
  FROM Tags AS t
  WHERE
    t.TagName LIKE 'c#%'
  UNION ALL
  SELECT
    th.TagId,
    th.TagName,
    th.RootTagId,
    th.Depth + 1
  FROM TagHierarchy AS th
  JOIN Posts AS p
    ON th.TagName = SUBSTRING(p.Tags, 2, CHARINDEX('>', p.Tags) - 2)
  JOIN Tags AS t
    ON SUBSTRING(p.Tags, CHARINDEX('>', p.Tags) + 1, CHARINDEX('>', p.Tags, CHARINDEX('>', p.Tags) + 1) - CHARINDEX('>', p.Tags) - 1) = t.TagName
  WHERE
    th.Depth < 3
), RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    p.ViewCount,
    p.FavoriteCount,
    p.CreationDate,
    p.LastActivityDate,
    u.DisplayName AS OwnerDisplayName,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS RowNumByUser,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY p.OwnerUserId) AS QuestionCount,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgScoreByUser,
    COUNT(c.Id) OVER (PARTITION BY p.OwnerUserId) AS CommentCountByUser,
    RANK() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank
  FROM Posts AS p
  LEFT JOIN Users AS u
    ON p.OwnerUserId = u.Id
  LEFT JOIN Comments AS c
    ON p.Id = c.PostId
  WHERE
    p.PostTypeId = 1 AND p.Score > 10 AND p.CreationDate > '2023-01-01'
), PostTagCounts AS (
  SELECT
    p.Id AS PostId,
    COUNT(t.Id) AS NumberOfTags
  FROM Posts AS p
  JOIN Tags AS t
    ON p.Tags LIKE '%' + t.TagName + '%'
  WHERE
    p.PostTypeId = 1
  GROUP BY
    p.Id
), UserActivity AS (
  SELECT
    UserId,
    COUNT(Id) AS VoteCount,
    SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
    MAX(CreationDate) AS LastVoteDate
  FROM Votes
  WHERE
    VoteTypeId IN (2, 3)
  GROUP BY
    UserId
  HAVING
    COUNT(Id) > 50
), CommunityPosts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.CommunityOwnedDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CommunityOwnedDate ASC) AS CommunityOwnedRank
  FROM Posts AS p
  WHERE
    p.CommunityOwnedDate IS NOT NULL
)
SELECT
  rp.PostId,
  rp.Title,
  rp.OwnerDisplayName,
  rp.Score,
  rp.AnswerCount,
  rp.CommentCount,
  rp.ViewCount,
  rp.FavoriteCount,
  rp.CreationDate,
  rp.LastActivityDate,
  rp.RowNumByUser,
  rp.QuestionCount,
  rp.AvgScoreByUser,
  rp.CommentCountByUser,
  rp.PostRank,
  ptc.NumberOfTags,
  ua.VoteCount,
  ua.UpVoteCount,
  ua.DownVoteCount,
  ua.LastVoteDate,
  CASE
    WHEN cp.CommunityOwnedRank = 1 THEN 'FirstCommunityOwned'
    WHEN cp.CommunityOwnedRank > 1 THEN 'SubsequentCommunityOwned'
    ELSE 'NotCommunityOwned'
  END AS CommunityOwnershipStatus,
  COALESCE(th.TagName, 'No C# Tag') AS PrimaryCSharpCategory,
  CONCAT(rp.OwnerDisplayName, ' (', rp.Reputation, ')') AS OwnerInfo,
  IIF(rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1), 'Above Average Score', 'Below Average Score') AS ScoreComparison,
  'Has Answers' AS AnswerStatus
FROM RankedPosts AS rp
LEFT JOIN PostTagCounts AS ptc
  ON rp.PostId = ptc.PostId
LEFT JOIN UserActivity AS ua
  ON rp.OwnerUserId = ua.UserId
LEFT JOIN CommunityPosts AS cp
  ON rp.PostId = cp.PostId AND cp.CommunityOwnedRank = 1
LEFT JOIN TagHierarchy AS th
  ON rp.Tags LIKE '%' + th.TagName + '%' AND th.Depth = 0
LEFT JOIN Users AS u
  ON rp.OwnerUserId = u.Id
WHERE
  rp.Score > 50
  AND rp.AnswerCount > 5
  AND rp.ViewCount > 1000
  AND rp.OwnerUserId IS NOT NULL
  AND rp.OwnerDisplayName <> 'Community'
  AND COALESCE(rp.FavoriteCount, 0) > 0
  AND rp.LastActivityDate > DATEADD(month, -6, GETDATE())
  OR (rp.Score > 200 AND rp.AnswerCount > 10)
ORDER BY
  rp.PostRank;
