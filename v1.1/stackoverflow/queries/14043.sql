-- {"query": "14043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 102740, "output_tokens": 43392} 
WITH cte AS (
  SELECT p.Id, p.PostTypeId, p.CreationDate, p.Score, p.AnswerCount, p.CommentCount, p.FavoriteCount, u.Reputation, u.Views, u.UpVotes, u.DownVotes,
         CASE WHEN p.PostTypeId = 1 THEN p.AcceptedAnswerId ELSE p.ParentId END AS ParentId,
         CASE WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) ELSE NULL END AS QuestionUpVotes,
         CASE WHEN p.PostTypeId = 2 THEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) ELSE NULL END AS AnswerUpVotes,
         CASE WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) ELSE NULL END AS QuestionDownVotes,
         CASE WHEN p.PostTypeId = 2 THEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) ELSE NULL END AS AnswerDownVotes,
         CASE WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5) ELSE NULL END AS QuestionFavorites,
         CASE WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 7) ELSE NULL END AS QuestionReopenVotes,
         CASE WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 6) ELSE NULL END AS QuestionCloseVotes
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
)
SELECT 
  DENSE_RANK() OVER (PARTITION BY CAST(cte.CreationDate AS DATE) ORDER BY cte.Score DESC) AS DailyRank,
  cte.Id,
  cte.PostTypeId,
  cte.CreationDate,
  cte.Score,
  cte.AnswerCount,
  cte.CommentCount,
  cte.FavoriteCount,
  cte.Reputation,
  cte.Views,
  cte.UpVotes,
  cte.DownVotes,
  COALESCE(cte.QuestionUpVotes, cte.AnswerUpVotes) AS TotalUpVotes,
  COALESCE(cte.QuestionDownVotes, cte.AnswerDownVotes) AS TotalDownVotes,
  cte.QuestionFavorites,
  cte.QuestionReopenVotes,
  cte.QuestionCloseVotes,
  CASE WHEN cte.ParentId IS NOT NULL THEN 'Answer' ELSE 'Question' END AS PostType
FROM cte
WHERE cte.PostTypeId IN (1, 2)
ORDER BY cte.CreationDate DESC, cte.Score DESC;