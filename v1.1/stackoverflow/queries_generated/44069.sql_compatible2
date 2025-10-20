WITH cte AS (
  SELECT p.Id, p.CreationDate, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount AS PostFavoriteCount, p.CommentCount AS PostCommentCount,
         CASE WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) ELSE 0 END AS DuplicateCount,
         CASE WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 11)) ELSE 0 END AS CloseReopenCount,
         CASE WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (6, 7)) ELSE 0 END AS VoteCloseReopenCount,
         CASE WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) ELSE 0 END AS UpvoteCount,
         CASE WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) ELSE 0 END AS DownvoteCount,
         CASE WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5) ELSE 0 END AS FavoriteCount,
         CASE WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) ELSE 0 END AS CommentCount
  FROM Posts p
)
SELECT 
  CAST(EXTRACT(EPOCH FROM (MAX(CreationDate) - MIN(CreationDate))) / 60.0 AS NUMERIC(10,2)) AS MinutesRange,
  COUNT(*) AS TotalPosts,
  AVG(Score) AS AvgScore,
  AVG(ViewCount) AS AvgViewCount,
  AVG(AnswerCount) AS AvgAnswerCount,
  AVG(FavoriteCount) AS AvgFavoriteCount,
  AVG(CommentCount) AS AvgCommentCount,
  AVG(DuplicateCount) AS AvgDuplicateCount,
  AVG(CloseReopenCount) AS AvgCloseReopenCount,
  AVG(VoteCloseReopenCount) AS AvgVoteCloseReopenCount,
  AVG(UpvoteCount) AS AvgUpvoteCount,
  AVG(DownvoteCount) AS AvgDownvoteCount
FROM cte;