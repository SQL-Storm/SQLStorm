-- {"query": "1095.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 490} 

WITH UserReputation AS (
    SELECT Id, Reputation AS UserReputation, 
           CASE 
               WHEN Reputation >= 5000 THEN 'High'
               WHEN Reputation >= 1000 THEN 'Medium'
               ELSE 'Low' 
           END AS ReputationLevel
    FROM Users
),
PostStats AS (
    SELECT p.Id AS PostId, 
           p.PostTypeId, 
           p.Score, 
           p.CreationDate, 
           COUNT(c.Id) AS CommentCount,
           COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVoteCount,
           COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVoteCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id, p.PostTypeId, p.Score, p.CreationDate
),
UserPostStats AS (
    SELECT ur.Id AS UserId,
           ur.UserReputation,
           ps.PostId,
           ps.Score,
           ps.CommentCount,
           COALESCE(ps.UpVoteCount, 0) AS UpVoteCount,
           COALESCE(ps.DownVoteCount, 0) AS DownVoteCount,
           ROW_NUMBER() OVER (PARTITION BY ur.Id ORDER BY ps.CreationDate DESC) AS Rank
    FROM UserReputation ur
    JOIN Posts p ON ur.Id = p.OwnerUserId
    LEFT JOIN PostStats ps ON p.Id = ps.PostId
)
SELECT ups.UserId,
       ups.UserReputation,
       ups.PostId,
       ups.Score,
       ups.CommentCount,
       ups.UpVoteCount,
       ups.DownVoteCount,
       CASE 
           WHEN ups.UpVoteCount > ups.DownVoteCount THEN 'Positive'
           WHEN ups.UpVoteCount < ups.DownVoteCount THEN 'Negative'
           ELSE 'Neutral' 
       END AS VoteSentiment,
       (SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.PostId = ups.PostId AND ph.PostHistoryTypeId IN (10, 11)) AS CloseReopenCount
FROM UserPostStats ups
WHERE ups.Rank <= 5 AND ups.UserReputation > 1000
ORDER BY ups.UserReputation DESC, ups.Score DESC;
