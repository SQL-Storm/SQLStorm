-- {"query": "5659.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 698} 
WITH recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_by_user
  FROM Posts p
  WHERE p.PostTypeId = 1  -- questions
),
popular_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate,
    u.LastAccessDate,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Views DESC, u.LastAccessDate DESC) AS rn_user
  FROM Users u
  JOIN Badges b ON b.UserId = u.Id
  WHERE b.Class IN (1,2,3) -- any badge
),
tag_rich_qs AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.LastActivityDate,
    r.Tags,
    string_to_array(substring(r.Tags, 2, length(r.Tags)-2), '><') AS tag_list
  FROM recent_activity r
),
score_bucket AS (
  SELECT
    po.PostId,
    po.Title,
    po.CreationDate,
    po.LastActivityDate,
    po.Score,
    CASE
      WHEN po.Score >= 50 THEN 'A'
      WHEN po.Score >= 20 THEN 'B'
      WHEN po.Score >= 5 THEN 'C'
      WHEN po.Score >= 0 THEN 'D'
      ELSE 'E'
    END AS score_group,
    COUNT(*) OVER () AS total
  FROM recent_activity po
)
SELECT
  pu.UserId,
  pu.DisplayName AS UserDisplayName,
  pu.Reputation,
  pu.Views,
  pu.UpVotes,
  pu.DownVotes,
  pu.CreationDate AS UserCreationDate,
  pu.LastAccessDate AS UserLastAccessDate,
  rb.PostId,
  rb.Title AS QuestionTitle,
  rb.CreationDate AS QuestionCreationDate,
  rb.LastActivityDate AS QuestionLastActivityDate,
  rb.Tags,
  qa.tag_list AS TagList,
  sb.score_group,
  sb.total AS TotalQuestionsInBuckets,
  -- Join to posts' first comment as an illustrative correlated subquery
  (SELECT c.Text
     FROM Comments c
     WHERE c.PostId = rb.PostId
     ORDER BY c.CreationDate ASC
     LIMIT 1) AS FirstCommentText,
  -- Window function over authors to show rank within their reputation tier
  DENSE_RANK() OVER (PARTITION BY pu.Reputation / 1000
                   ORDER BY pu.Reputation DESC) AS ReputationTierRank
FROM popular_users pu
JOIN tag_rich_qs rb
  ON rb.PostId = rb.PostId
JOIN LATERAL (
  SELECT tag_list
) qa ON true
JOIN score_bucket sb
  ON sb.PostId = rb.PostId
WHERE pu.rn_user <= 100
  AND rb.rn_by_user = 1
ORDER BY pu.Reputation DESC, rb.LastActivityDate DESC
LIMIT 200;