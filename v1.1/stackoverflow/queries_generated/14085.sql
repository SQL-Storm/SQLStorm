-- {"query": "14085.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 1311}
WITH cte AS (
  SELECT p.Id, p.PostTypeId, p.ParentId, p.OwnerUserId, p.LastEditorUserId, p.Title, p.Tags, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate,
         CASE WHEN p.PostTypeId = 1 THEN p.AcceptedAnswerId ELSE p.Id END AS AcceptedAnswerId,
         CASE WHEN p.PostTypeId = 2 THEN p.ParentId ELSE NULL END AS ParentQuestionId,
         COALESCE(p.CreationDate, p.LastActivityDate) AS CreationDate,
         CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
              WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
              ELSE 'Open' END AS PostStatus,
         CASE WHEN p.OwnerUserId = p.LastEditorUserId THEN 'Owner'
              WHEN p.OwnerUserId IS NULL THEN 'Community'
              ELSE 'Edited' END AS PostOwnerType
  FROM Posts p
),
post_stats AS (
  SELECT c.Id, c.PostTypeId, c.ParentId, c.OwnerUserId, c.LastEditorUserId, c.Title, c.Tags, c.AnswerCount, c.CommentCount, c.FavoriteCount, c.ClosedDate, c.CommunityOwnedDate, c.AcceptedAnswerId, c.ParentQuestionId, c.CreationDate, c.PostStatus, c.PostOwnerType,
         COUNT(DISTINCT v.Id) AS VoteCount,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
         SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCount AS FavoriteCount_old,
         SUM(CASE WHEN v.VoteTypeId IN (6, 7) THEN 1 ELSE 0 END) AS CloseReopenVoteCount
  FROM cte c
  LEFT JOIN Votes v ON c.Id = v.PostId
  GROUP BY c.Id, c.PostTypeId, c.ParentId, c.OwnerUserId, c.LastEditorUserId, c.Title, c.Tags, c.AnswerCount, c.CommentCount, c.FavoriteCount, c.ClosedDate, c.CommunityOwnedDate, c.AcceptedAnswerId, c.ParentQuestionId, c.CreationDate, c.PostStatus, c.PostOwnerType
),
post_history AS (
  SELECT p.Id, p.PostHistoryTypeId, p.PostId, p.CreationDate, p.UserId, p.UserDisplayName, p.Comment, p.Text, p.ContentLicense
  FROM PostHistory p
  WHERE p.PostHistoryTypeId IN (1, 4, 5, 6, 10, 11, 12, 13, 14, 15, 19, 20)
),
post_links AS (
  SELECT pl.Id, pl.CreationDate, pl.PostId, pl.RelatedPostId, pl.LinkTypeId, lt.Name AS LinkTypeName
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
)
SELECT
  ps.Id AS PostId,
  ps.PostTypeId,
  ps.ParentId,
  ps.OwnerUserId,
  ps.LastEditorUserId,
  ps.Title,
  ps.Tags,
  ps.AnswerCount,
  ps.CommentCount,
  ps.FavoriteCount,
  ps.FavoriteCount_old,
  ps.ClosedDate,
  ps.CommunityOwnedDate,
  ps.AcceptedAnswerId,
  ps.ParentQuestionId,
  ps.CreationDate,
  ps.PostStatus,
  ps.PostOwnerType,
  ps.VoteCount,
  ps.UpVoteCount,
  ps.DownVoteCount,
  ps.CloseReopenVoteCount,
  ph.PostHistoryTypeId,
  ph.CreationDate AS HistoryCreationDate,
  ph.UserId AS HistoryUserId,
  ph.UserDisplayName AS HistoryUserDisplayName,
  ph.Comment AS HistoryComment,
  ph.Text AS HistoryText,
  ph.ContentLicense AS HistoryContentLicense,
  pl.Id AS LinkId,
  pl.CreationDate AS LinkCreationDate,
  pl.RelatedPostId,
  pl.LinkTypeName
FROM post_stats ps
LEFT JOIN post_history ph ON ps.Id = ph.PostId
LEFT JOIN post_links pl ON ps.Id = pl.PostId
ORDER BY ps.Id, ph.CreationDate, pl.CreationDate;
