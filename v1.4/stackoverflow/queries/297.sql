-- {"query": "297.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 10456} 
WITH Base AS (
  SELECT
     u.Id AS UserId,
     u.DisplayName,
     u.LastAccessDate,
     u.Reputation AS ReputationScore,
     COALESCE(p.PostCount, 0) AS PostCount,
     COALESCE(cm.CommentCount, 0) AS CommentCount,
     COALESCE(v.UpVotes, 0) AS UpVotes,
     COALESCE(v.DownVotes, 0) AS DownVotes
  FROM Users u
  LEFT JOIN (
     SELECT OwnerUserId, COUNT(*) AS PostCount
     FROM Posts
     WHERE PostTypeId IN (1,2)
     GROUP BY OwnerUserId
  ) p ON p.OwnerUserId = u.Id
  LEFT JOIN (
     SELECT UserId, COUNT(*) AS CommentCount
     FROM Comments
     GROUP BY UserId
  ) cm ON cm.UserId = u.Id
  LEFT JOIN (
     SELECT UserId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
     FROM Votes
     GROUP BY UserId
  ) v ON v.UserId = u.Id
),
ReputationView AS (
  SELECT
     b.UserId,
     b.DisplayName,
     b.ReputationScore AS Score,
     (SELECT CreationDate FROM Posts p2 WHERE p2.OwnerUserId = b.UserId ORDER BY p2.CreationDate DESC LIMIT 1) AS LastPostDate,
     (SELECT Title FROM Posts p2 WHERE p2.OwnerUserId = b.UserId ORDER BY p2.CreationDate DESC LIMIT 1) AS LastPostTitle,
     (SELECT LastEditorDisplayName FROM Posts p3 WHERE p3.OwnerUserId = b.UserId ORDER BY p3.LastEditDate DESC LIMIT 1) AS LastEditedBy,
     b.LastAccessDate,
     'Reputation' AS Source
  FROM Base b
),
ActivityView AS (
  SELECT
     b.UserId,
     b.DisplayName,
     (b.PostCount * 3 + b.CommentCount + b.UpVotes - b.DownVotes) AS Score,
     (SELECT CreationDate FROM Posts p2 WHERE p2.OwnerUserId = b.UserId ORDER BY p2.CreationDate DESC LIMIT 1) AS LastPostDate,
     (SELECT Title FROM Posts p2 WHERE p2.OwnerUserId = b.UserId ORDER BY p2.CreationDate DESC LIMIT 1) AS LastPostTitle,
     (SELECT LastEditorDisplayName FROM Posts p3 WHERE p3.OwnerUserId = b.UserId ORDER BY p3.LastEditDate DESC LIMIT 1) AS LastEditedBy,
     b.LastAccessDate,
     'Activity' AS Source
  FROM Base b
)
SELECT
  UserId,
  DisplayName,
  Score,
  LastPostDate,
  LastPostTitle,
  LastEditedBy,
  LastAccessDate,
  Source
FROM (
  SELECT * FROM ReputationView
  UNION ALL
  SELECT * FROM ActivityView
) AS Combined
ORDER BY Score DESC
LIMIT 200;