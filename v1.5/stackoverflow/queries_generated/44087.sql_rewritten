-- {"query": "44087.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 199578, "output_tokens": 68797} 
WITH cte AS (
    SELECT 
        p.Id, 
        p.CreationDate, 
        p.Score, 
        p.AnswerCount, 
        p.CommentCount, 
        p.FavoriteCount, 
        u.Reputation, 
        u.UpVotes, 
        u.DownVotes,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS score_rank,
        DENSE_RANK() OVER (ORDER BY p.AnswerCount DESC) AS answer_rank,
        DENSE_RANK() OVER (ORDER BY p.CommentCount DESC) AS comment_rank,
        DENSE_RANK() OVER (ORDER BY p.FavoriteCount DESC) AS favorite_rank,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS reputation_rank,
        DENSE_RANK() OVER (ORDER BY u.UpVotes DESC) AS upvote_rank,
        DENSE_RANK() OVER (ORDER BY u.DownVotes DESC) AS downvote_rank
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
)
SELECT 
    Id,
    CreationDate,
    Score,
    AnswerCount,
    CommentCount,
    FavoriteCount,
    Reputation,
    UpVotes,
    DownVotes,
    score_rank,
    answer_rank,
    comment_rank,
    favorite_rank,
    reputation_rank,
    upvote_rank,
    downvote_rank
FROM cte
WHERE score_rank <= 10
   OR answer_rank <= 10
   OR comment_rank <= 10
   OR favorite_rank <= 10
   OR reputation_rank <= 10
   OR upvote_rank <= 10
   OR downvote_rank <= 10
ORDER BY CreationDate DESC
LIMIT 100;