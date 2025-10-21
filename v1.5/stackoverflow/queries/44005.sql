-- {"query": "44005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 11470, "output_tokens": 4737} 
WITH cte AS (
  SELECT p.Id AS PostId, p.PostTypeId, p.CreationDate, p.OwnerUserId, p.Score, p.ViewCount, p.CommentCount, p.FavoriteCount, p.AnswerCount, 
         u.Id AS UserId, u.Reputation, u.CreationDate AS UserCreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes,
         CASE WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) 
              ELSE (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3)) END AS TotalVotes,
         CASE WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3)
              ELSE (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) END AS TotalDownVotes,
         CASE WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) 
              ELSE (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) END AS TotalUpVotes,
         CASE WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5) 
              ELSE 0 END AS TotalFavorites
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.CreationDate >= '2020-01-01' AND p.CreationDate < '2021-01-01'
),
agg AS (
  SELECT PostId, 
         MAX(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS IsQuestion,
         MAX(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS IsAnswer,
         SUM(Score) AS TotalScore,
         SUM(ViewCount) AS TotalViewCount,
         SUM(CommentCount) AS TotalCommentCount,
         SUM(FavoriteCount) AS TotalFavoriteCount,
         SUM(AnswerCount) AS TotalAnswerCount,
         MAX(UserId) AS OwnerUserId,
         MAX(Reputation) AS OwnerReputation,
         MAX(UserCreationDate) AS OwnerCreationDate,
         MAX(LastAccessDate) AS OwnerLastAccessDate,
         MAX(Views) AS OwnerViews,
         MAX(UpVotes) AS OwnerUpVotes,
         MAX(DownVotes) AS OwnerDownVotes,
         SUM(TotalVotes) AS TotalVotes,
         SUM(TotalDownVotes) AS TotalDownVotes,
         SUM(TotalUpVotes) AS TotalUpVotes,
         SUM(TotalFavorites) AS TotalFavorites
  FROM cte
  GROUP BY PostId
)
SELECT *
FROM agg
ORDER BY TotalScore DESC, TotalViewCount DESC, TotalCommentCount DESC, TotalFavoriteCount DESC, TotalAnswerCount DESC;