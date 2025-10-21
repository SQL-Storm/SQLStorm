-- {"query": "14017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 497}
WITH cte AS (
    SELECT p.Id, p.Title, p.Body, p.Tags, p.OwnerUserId, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes,
           RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rk
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
)
SELECT *
FROM cte
WHERE rk = 1
ORDER BY Reputation DESC, Views DESC, UpVotes DESC, DownVotes ASC
LIMIT 10;

WITH latest_edits AS (
    SELECT ph.PostId, MAX(ph.CreationDate) AS last_edit_date
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY ph.PostId
)
SELECT p.Id, p.Title, p.Body, p.Tags, u.DisplayName, u.Reputation, le.last_edit_date
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
JOIN latest_edits le ON p.Id = le.PostId
ORDER BY le.last_edit_date DESC
LIMIT 10;

SELECT p.Id, p.Title, p.Body, p.Tags, COALESCE(u.DisplayName, 'Community') AS DisplayName, 
       COALESCE(u.Reputation, 1) AS Reputation, v.VoteTypeId, COUNT(*) AS VoteCount
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
GROUP BY p.Id, p.Title, p.Body, p.Tags, u.DisplayName, u.Reputation, v.VoteTypeId
ORDER BY VoteCount DESC
LIMIT 10;
