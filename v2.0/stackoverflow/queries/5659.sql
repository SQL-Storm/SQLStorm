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
  WHERE p.PostTypeId = 1
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
  WHERE b.Class IN (1,2,3)
),
tag_rich_qs AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.LastActivityDate,
    r.Tags,
    -- portable splitting: remove leading/trailing angle brackets and split on '><'
    CASE
      WHEN r.Tags IS NULL THEN NULL
      WHEN LENGTH(r.Tags) >= 2 THEN
        -- replace '><' with a delimiter and then split; here we return a CSV string of tags for portability
        REPLACE(SUBSTRING(r.Tags FROM 2 FOR LENGTH(r.Tags) - 2), '><', ',') 
      ELSE
        NULL
    END AS tag_list_csv
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
  qa.tag_list_csv AS TagListCSV,
  sb.score_group,
  sb.total AS TotalQuestionsInBuckets,
  (
    SELECT c.Text
    FROM Comments c
    WHERE c.PostId = rb.PostId
    ORDER BY c.CreationDate ASC
    FETCH FIRST 1 ROWS ONLY
  ) AS FirstCommentText,
  DENSE_RANK() OVER (PARTITION BY FLOOR(pu.Reputation / 1000) ORDER BY pu.Reputation DESC) AS ReputationTierRank
FROM popular_users pu
JOIN recent_activity ra
  ON ra.OwnerUserId = pu.UserId
JOIN tag_rich_qs rb
  ON rb.PostId = ra.PostId
JOIN LATERAL (
  SELECT rb.tag_list_csv AS tag_list_csv
) qa ON TRUE
JOIN score_bucket sb
  ON sb.PostId = rb.PostId
WHERE pu.rn_user <= 100
  AND ra.rn_by_user = 1
GROUP BY
  pu.UserId,
  pu.DisplayName,
  pu.Reputation,
  pu.Views,
  pu.UpVotes,
  pu.DownVotes,
  pu.CreationDate,
  pu.LastAccessDate,
  rb.PostId,
  rb.Title,
  rb.CreationDate,
  rb.LastActivityDate,
  rb.Tags,
  qa.tag_list_csv,
  sb.score_group,
  sb.total,
  ra.rn_by_user
ORDER BY pu.Reputation DESC, rb.LastActivityDate DESC
FETCH FIRST 200 ROWS ONLY;