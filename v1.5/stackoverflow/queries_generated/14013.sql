-- {"query": "14013.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 1445}
WITH cte AS (
  SELECT 
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Body,
    p.Tags,
    p.OwnerUserId,
    p.LastEditorUserId,
    p.CreationDate,
    p.LastEditDate,
    p.ClosedDate,
    p.CommunityOwnedDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Score,
    p.ViewCount,
    CASE WHEN p.PostTypeId = 2 THEN p.ParentId ELSE NULL END AS ParentId,
    CASE WHEN p.PostTypeId = 1 THEN p.AcceptedAnswerId ELSE NULL END AS AcceptedAnswerId,
    COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerDisplayName,
    COALESCE(u2.DisplayName, p.LastEditorDisplayName) AS LastEditorDisplayName,
    CASE 
      WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
      WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
      WHEN p.AnswerCount = 0 THEN 'Unanswered'
      WHEN p.Score < 0 THEN 'Negative Score'
      ELSE 'Open'
    END AS PostStatus
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Users u2 ON p.LastEditorUserId = u2.Id
),
benchmarks AS (
  SELECT
    PostId,
    PostTypeId,
    Title,
    Body,
    Tags,
    OwnerUserId,
    LastEditorUserId,
    CreationDate,
    LastEditDate,
    ClosedDate,
    CommunityOwnedDate,
    AnswerCount,
    CommentCount,
    FavoriteCount,
    Score,
    ViewCount,
    ParentId,
    AcceptedAnswerId,
    OwnerDisplayName,
    LastEditorDisplayName,
    PostStatus,
    DATEDIFF(MINUTE, CreationDate, LastEditDate) AS TimeBetweenCreationAndLastEdit,
    DATEDIFF(MINUTE, CreationDate, COALESCE(ClosedDate, COALESCE(CommunityOwnedDate, LastActivityDate))) AS TimeBetweenCreationAndClose,
    CASE
      WHEN ClosedDate IS NOT NULL THEN 'Closed'
      WHEN CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
      WHEN AnswerCount = 0 THEN 'Unanswered'
      WHEN Score < 0 THEN 'Negative Score'
      ELSE 'Open'
    END AS PostStatusCategory,
    CASE 
      WHEN Tags LIKE '%<javascript>%' THEN 'JavaScript'
      WHEN Tags LIKE '%<python>%' THEN 'Python'
      WHEN Tags LIKE '%<java>%' THEN 'Java'
      WHEN Tags LIKE '%<c#>%' THEN 'C#'
      WHEN Tags LIKE '%<php>%' THEN 'PHP'
      ELSE 'Other'
    END AS MainTag,
    CONCAT(SUBSTRING(Tags, 2, CHARINDEX('><', Tags) - 2), ', ', REPLACE(SUBSTRING(Tags, CHARINDEX('><', Tags) + 2, LEN(Tags) - CHARINDEX('><', Tags) - 2), '><', ', ')) AS TagList
  FROM cte
)
SELECT
  PostId,
  PostTypeId,
  Title,
  Body,
  Tags,
  OwnerUserId,
  LastEditorUserId,
  CreationDate,
  LastEditDate,
  ClosedDate,
  CommunityOwnedDate,
  AnswerCount,
  CommentCount,
  FavoriteCount,
  Score,
  ViewCount,
  ParentId,
  AcceptedAnswerId,
  OwnerDisplayName,
  LastEditorDisplayName,
  PostStatus,
  TimeBetweenCreationAndLastEdit,
  TimeBetweenCreationAndClose,
  PostStatusCategory,
  MainTag,
  TagList,
  (CASE WHEN PostTypeId = 1 THEN 
    (SELECT COUNT(*) 
     FROM Votes v
     WHERE v.PostId = b.PostId AND v.VoteTypeId = 2)
   ELSE NULL END) AS UpVotes,
  (CASE WHEN PostTypeId = 1 THEN
    (SELECT COUNT(*)
     FROM Votes v
     WHERE v.PostId = b.PostId AND v.VoteTypeId = 3)
   ELSE NULL END) AS DownVotes,
  (CASE WHEN PostTypeId = 1 THEN
    (SELECT COUNT(*)
     FROM Votes v
     WHERE v.PostId = b.PostId AND v.VoteTypeId = 5)
   ELSE NULL END) AS Favorites,
  (CASE WHEN PostTypeId = 2 THEN
    (SELECT COUNT(*)
     FROM Comments c
     WHERE c.PostId = b.PostId)
   ELSE NULL END) AS CommentCountOnAnswer,
  (CASE WHEN PostTypeId = 2 THEN
    (SELECT p.Score
     FROM Posts p
     WHERE p.Id = b.ParentId)
   ELSE NULL END) AS ParentPostScore
FROM benchmarks b
ORDER BY Score DESC, ViewCount DESC, AnswerCount DESC, CommentCount DESC, FavoriteCount DESC;
