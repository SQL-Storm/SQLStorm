-- {"query": "5230.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 807}
WITH RecentQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    u.Reputation,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
CommonActivity AS (
  SELECT
    q.PostId,
    q.Title,
    q.OwnerName,
    q.Reputation,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    COALESCE(pc.TotalComments, 0) AS CommentCount,
    COALESCE(v.UpVote, 0) AS UpVotes,
    COALESCE(v.DownVote, 0) AS DownVotes,
    STRING_AGG(DISTINCT COALESCE(l.LinkTypesUsed, ''), ',') AS LinkTypesUsed,
    q.Tags,
    EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - q.CreationDate)) / 3600 AS HoursSinceCreation
  FROM RecentQuestions q
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS TotalComments
    FROM Comments
    GROUP BY PostId
  ) pc ON pc.PostId = q.PostId
  LEFT JOIN (
    SELECT v.PostId,
           SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVote,
           SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVote
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY v.PostId
  ) v ON v.PostId = q.PostId
  LEFT JOIN (
    SELECT pl.PostId,
           STRING_AGG(lt.Name, ',') AS LinkTypesUsed
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE lt.Id IN (1,3)
    GROUP BY pl.PostId
  ) l ON l.PostId = q.PostId
  GROUP BY
    q.PostId, q.Title, q.OwnerName, q.Reputation, q.CreationDate, q.ViewCount, q.Score,
    pc.TotalComments, v.UpVote, v.DownVote, q.Tags
)
SELECT
  ca.PostId,
  ca.Title,
  ca.OwnerName,
  ca.Reputation,
  ca.CreationDate,
  ca.ViewCount,
  ca.Score,
  ca.CommentCount,
  ca.UpVotes,
  ca.DownVotes,
  ca.LinkTypesUsed,
  ca.Tags,
  ca.HoursSinceCreation,
  AVG(ca.Score) OVER (
    PARTITION BY ca.OwnerName
    ORDER BY ca.CreationDate
    ROWS BETWEEN 9 PRECEDING AND CURRENT ROW
  ) AS RunningAvgLast10Scores,
  CASE
    WHEN ca.ViewCount > 1000 OR ca.Score > 10 THEN 'High Engagement'
    WHEN ca.CommentCount > 20 THEN 'Active Discussion'
    ELSE 'Moderate'
  END AS EngagementBucket
FROM CommonActivity ca
ORDER BY ca.CreationDate DESC
LIMIT 100;