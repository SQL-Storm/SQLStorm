-- {"query": "5339.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 598} 
WITH top_users AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    COUNT(p.Id) AS post_count,
    AVG(p.Score) AS avg_post_score,
    MAX(p.LastActivityDate) AS last_activity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    u.Location, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
recent_interactions AS (
  SELECT
    u.Id AS UserId,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS upvotes_cast,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS downvotes_cast,
    COUNT(c.Id) AS comments_made,
    COUNT(b.Id) AS badges_awarded
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id
),
tag_interest AS (
  SELECT
    p.OwnerUserId AS UserId,
    unnest(string_to_array(lower(p.Tags), '><')) AS tag
  FROM Posts p
  WHERE p.PostTypeId = 1
),
tag_trends AS (
  SELECT
    tag,
    COUNT(*) AS tag_count,
    AVG(p.Score) AS avg_score
  FROM Posts p
  JOIN UNNEST(string_to_array(lower(p.Tags), '><')) AS tag ON true
  WHERE p.PostTypeId = 1
  GROUP BY tag
  ORDER BY tag_count DESC
  LIMIT 5
)
SELECT
  tu.Id,
  tu.DisplayName,
  tu.Reputation,
  tu.post_count,
  tu.avg_post_score,
  ri.upvotes_cast,
  ri.downvotes_cast,
  ri.comments_made,
  ri.badges_awarded,
  tu.last_activity,
  tr.tag AS top_tag_considered,
  tt.tag_count AS tag_frequency,
  tt.avg_score AS tag_avg_post_score
FROM top_users tu
LEFT JOIN recent_interactions ri ON ri.UserId = tu.Id
LEFT JOIN tag_interest ti ON ti.UserId = tu.Id
LEFT JOIN tag_trends tt ON true
LEFT JOIN (
  SELECT tag, tag_count, avg_score
  FROM tag_trends
) tt ON true
ORDER BY tu.Reputation DESC, tu.post_count DESC
LIMIT 100;