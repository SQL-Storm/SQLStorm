-- {"query": "230.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 5976} 
WITH per_user AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(p.Id) AS PostCount,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS NetVotes,
    MAX(GREATEST(COALESCE(p.LastActivityDate, TIMESTAMP '1900-01-01'), COALESCE(u.LastAccessDate, TIMESTAMP '1900-01-01'))) AS LastActive,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName
),
tag_agg AS (
  SELECT
    p.OwnerUserId AS UserId,
    t.TagName,
    COUNT(*) AS TagUsage
  FROM Posts p
  CROSS JOIN LATERAL regexp_split_to_table(substring(p.Tags, 2, length(p.Tags)-2), '><') AS t(TagName)
  GROUP BY p.OwnerUserId, t.TagName
),
top_tag_per_user AS (
  SELECT UserId, TagName, TagUsage,
         ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagUsage DESC, TagName ASC) AS rn
  FROM tag_agg
),
user_top_tag AS (
  SELECT UserId,
         MAX(CASE WHEN rn = 1 THEN TagName END) AS TopTag,
         MAX(CASE WHEN rn = 1 THEN TagUsage END) AS TopTagUses
  FROM top_tag_per_user
  GROUP BY UserId
)

SELECT
  pu.UserId,
  pu.DisplayName,
  pu.PostCount,
  pu.NetVotes,
  pu.LastActive,
  pu.BadgeCount,
  COALESCE(ut.TopTag, '') AS TopTag,
  COALESCE(ut.TopTagUses, 0) AS TopTagUses,
  ROW_NUMBER() OVER (ORDER BY pu.NetVotes DESC NULLS LAST, pu.PostCount DESC) AS NetRank
FROM per_user pu
LEFT JOIN user_top_tag ut ON ut.UserId = pu.UserId

UNION ALL

SELECT
  0 AS UserId,
  'Summary' AS DisplayName,
  (SELECT SUM(PostCount) FROM per_user) AS PostCount,
  (SELECT SUM(NetVotes) FROM per_user) AS NetVotes,
  (SELECT MAX(LastActive) FROM per_user) AS LastActive,
  (SELECT SUM(BadgeCount) FROM per_user) AS BadgeCount,
  '' AS TopTag,
  0 AS TopTagUses,
  0 AS NetRank;