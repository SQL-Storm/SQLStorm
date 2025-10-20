-- {"query": "14034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 81725, "output_tokens": 35399} 
WITH cte AS (
  SELECT p.Id, p.Title, p.Body, p.CreationDate, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount,
         u.DisplayName AS OwnerDisplayName, u.Reputation AS OwnerReputation, u.Location, u.AboutMe, u.Views AS UserViews, u.UpVotes AS UserUpVotes, u.DownVotes AS UserDownVotes,
         CONCAT(SUBSTRING(p.Title, 1, 50), '...') AS TruncatedTitle,
         CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
         DATEDIFF(NOW(), p.CreationDate) AS DaysSinceCreation,
         ROUND(p.Score * 1.0 / (DATEDIFF(NOW(), p.CreationDate) + 1), 2) AS ScorePerDay,
         ROUND(p.ViewCount * 1.0 / (DATEDIFF(NOW(), p.CreationDate) + 1), 2) AS ViewsPerDay,
         ROUND(p.AnswerCount * 1.0 / (DATEDIFF(NOW(), p.CreationDate) + 1), 2) AS AnswersPerDay,
         ROUND(p.CommentCount * 1.0 / (DATEDIFF(NOW(), p.CreationDate) + 1), 2) AS CommentsPerDay,
         ROUND(u.Reputation * 1.0 / (DATEDIFF(NOW(), u.CreationDate) + 1), 2) AS ReputationPerDay,
         CASE WHEN p.PostTypeId = 1 THEN 'Question' WHEN p.PostTypeId = 2 THEN 'Answer' ELSE 'Other' END AS PostType,
         STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
         ROUND(COALESCE(CAST(SUBSTRING_INDEX(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><', 1) AS UNSIGNED), 0) * 1.0 / NULLIF(CAST(SUBSTRING_INDEX(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><', -1) AS UNSIGNED), 0), 2) AS TagScore,
         CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN (SELECT p2.Score FROM Posts p2 WHERE p2.Id = p.AcceptedAnswerId) ELSE 0 END AS AcceptedAnswerScore
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Tags t ON FIND_IN_SET(t.TagName, SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2)) > 0
  WHERE p.PostTypeId IN (1, 2)
  GROUP BY p.Id
)
SELECT *,
       CASE WHEN AcceptedAnswerScore > 0 THEN AcceptedAnswerScore / Score ELSE 0 END AS AcceptedAnswerRatio,
       CASE WHEN Tags IS NOT NULL THEN LENGTH(REPLACE(Tags, ',', '')) - LENGTH(REPLACE(Tags, ',', '')) + 1 ELSE 0 END AS NumTags,
       CASE WHEN PostType = 'Question' THEN 
           COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = cte.Id AND v.VoteTypeId = 2), 0)
         ELSE 
           COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = cte.Id AND v.VoteTypeId = 2), 0) + 
           COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = (SELECT ParentId FROM Posts WHERE Id = cte.Id) AND v.VoteTypeId = 2), 0)
       END AS UpVotes,
       CASE WHEN PostType = 'Question' THEN
           COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = cte.Id AND v.VoteTypeId = 3), 0)
         ELSE
           COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = cte.Id AND v.VoteTypeId = 3), 0) +
           COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = (SELECT ParentId FROM Posts WHERE Id = cte.Id) AND v.VoteTypeId = 3), 0)
       END AS DownVotes,
       CASE WHEN PostType = 'Question' THEN
           COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = cte.Id AND v.VoteTypeId = 5), 0)
         ELSE
           COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = cte.Id AND v.VoteTypeId = 5), 0) +
           COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = (SELECT ParentId FROM Posts WHERE Id = cte.Id) AND v.VoteTypeId = 5), 0)
       END AS Favorites
FROM cte;