-- {"query": "44048.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 110112, "output_tokens": 39477} 
Here is an elaborate SQL query for performance benchmarking:

WITH cte AS (
  SELECT p.Id, p.PostTypeId, p.CreationDate, p.OwnerUserId, p.LastEditorUserId, p.LastEditDate, p.LastActivityDate, p.Title, p.Tags, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate, u.Reputation, u.CreationDate AS UserCreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes, b.Id AS BadgeId, b.Name AS BadgeName, b.Date AS BadgeDate, b.Class AS BadgeClass, b.TagBased AS BadgeTagBased, c.Id AS CommentId, c.Score AS CommentScore, c.CreationDate AS CommentCreationDate, v.Id AS VoteId, v.VoteTypeId, v.CreationDate AS VoteCreationDate, v.BountyAmount
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON u.Id = b.UserId
  LEFT JOIN Comments c ON p.Id = c.PostId
  LEFT JOIN Votes v ON p.Id = v.PostId
)
SELECT
  COUNT(*) AS TotalPosts,
  COUNT(DISTINCT OwnerUserId) AS UniqueUsers,
  COUNT(DISTINCT BadgeId) AS UniqueBadges,
  COUNT(DISTINCT CommentId) AS UniqueComments,
  COUNT(DISTINCT VoteId) AS UniqueVotes,
  AVG(Reputation) AS AvgReputation,
  AVG(Views) AS AvgViews,
  AVG(UpVotes) AS AvgUpVotes,
  AVG(DownVotes) AS AvgDownVotes,
  AVG(AnswerCount) AS AvgAnswerCount,
  AVG(CommentCount) AS AvgCommentCount,
  AVG(FavoriteCount) AS AvgFavoriteCount,
  COUNT(CASE WHEN ClosedDate IS NOT NULL THEN 1 END) AS ClosedPosts,
  COUNT(CASE WHEN CommunityOwnedDate IS NOT NULL THEN 1 END) AS CommunityOwnedPosts,
  COUNT(DISTINCT CASE WHEN BadgeTagBased = 1 THEN BadgeId END) AS UniqueTagBadges,
  COUNT(DISTINCT CASE WHEN BadgeTagBased = 0 THEN BadgeId END) AS UniqueNamedBadges,
  COUNT(DISTINCT CASE WHEN VoteTypeId = 2 THEN VoteId END) AS UpVotes,
  COUNT(DISTINCT CASE WHEN VoteTypeId = 3 THEN VoteId END) AS DownVotes,
  COUNT(DISTINCT CASE WHEN VoteTypeId = 5 THEN VoteId END) AS FavoriteVotes,
  COUNT(DISTINCT CASE WHEN VoteTypeId = 8 THEN VoteId END) AS BountyStartVotes,
  COUNT(DISTINCT CASE WHEN VoteTypeId = 9 THEN VoteId END) AS BountyCloseVotes
FROM cte;