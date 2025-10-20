-- {"query": "54001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 6510} 
WITH recent_posts AS (
  SELECT p.Id AS PostId,
         p.PostTypeId,
         p.OwnerUserId,
         p.Score,
         p.ViewCount,
         p.Title,
         p.Tags,
         p.CreationDate
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '365 days'
),
tag_split AS (
  SELECT PostId,
         TRIM(SUBSTRING(Tags FROM 2 FOR LENGTH(Tags)-2)) AS tags_clean
  FROM recent_posts
),
tags AS (
  SELECT PostId,
         UNNEST(STRING_TO_ARRAY(tags_clean, '><')) AS tag
  FROM tag_split
),
vote_stats AS (
  SELECT v.PostId,
         COUNT(*) AS vote_count,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes
  FROM Votes v
  GROUP BY v.PostId
),
comment_stats AS (
  SELECT c.PostId,
         COUNT(*) AS comment_count
  FROM Comments c
  GROUP BY c.PostId
),
edit_stats AS (
  SELECT ph.PostId,
         COUNT(*) AS edit_count,
         MAX(ph.CreationDate) AS last_edit,
         MIN(ph.CreationDate) AS first_edit
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId = 5
  GROUP BY ph.PostId
),
tag_summary AS (
  SELECT t.tag AS Tag,
         COUNT(DISTINCT t.PostId) AS question_count,
         AVG(vs.vote_count) AS avg_votes,
         AVG(vs.up_votes) AS avg_up_votes,
         AVG(vs.down_votes) AS avg_down_votes,
         AVG(cs.comment_count) AS avg_comments,
         AVG(es.edit_count) AS avg_edits
  FROM tags t
  LEFT JOIN vote_stats vs ON vs.PostId = t.PostId
  LEFT JOIN comment_stats cs ON cs.PostId = t.PostId
  LEFT JOIN edit_stats es ON es.PostId = t.PostId
  GROUP BY t.tag
),
user_stats AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         COUNT(DISTINCT p.Id) AS TotalPosts,
         SUM(p.Score) AS TotalPostScore,
         COUNT(v.Id) AS TotalVotes,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
         COUNT(c.Id) AS TotalComments,
         SUM(ed.edit_count) AS TotalEdits
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  LEFT JOIN (
    SELECT ph.PostId, COUNT(*) AS edit_count
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 5
    GROUP BY ph.PostId
  ) ed ON ed.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT
  us.UserId,
  us.DisplayName,
  us.Reputation,
  us.TotalPosts,
  us.TotalPostScore,
  us.TotalVotes,
  us.TotalUpVotes,
  us.TotalDownVotes,
  us.TotalComments,
  us.TotalEdits,
  ts.*
FROM user_stats us
CROSS JOIN LATERAL (
  SELECT *
  FROM tag_summary
  ORDER BY question_count DESC
  LIMIT 5
) ts
ORDER BY us.Reputation DESC, ts.question_count DESC
LIMIT 20;