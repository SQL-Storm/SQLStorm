-- {"query": "5281.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 818}
WITH TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) AS PostCount,
    SUM(p.Score) AS ScoreSum,
    MAX(p.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE u.Reputation > 1000
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagHot AS (
  SELECT
    t.tag AS TagName,
    COUNT(p.Id) AS PostCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.LastActivityDate) AS LastActivity
  FROM Tags tg
  JOIN Posts p ON p.Id = tg.ExcerptPostId
  JOIN LATERAL (
    SELECT trim(BOTH '<>' FROM s_tag) AS tag
    FROM (
      SELECT unnest(string_to_array(p.Tags, '><')) AS s_tag
    ) sub
  ) t ON t.tag = tg.TagName
  WHERE tg.IsModeratorOnly = FALSE
  GROUP BY t.tag
),
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '7 days')
),
Combined AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.LastActivityDate,
    r.OwnerUserId,
    r.Score,
    r.ViewCount,
    r.CommentCount,
    r.UpVotes,
    r.DownVotes,
    CAST(NULL AS text) AS TagName,
    CAST(NULL AS integer) AS TagCount
  FROM RecentActivity r
  UNION ALL
  SELECT
    CAST(NULL AS bigint) AS PostId,
    CAST(NULL AS text) AS Title,
    CAST(NULL AS timestamp) AS CreationDate,
    CAST(NULL AS timestamp) AS LastActivityDate,
    CAST(NULL AS bigint) AS OwnerUserId,
    CAST(NULL AS integer) AS Score,
    CAST(NULL AS integer) AS ViewCount,
    CAST(NULL AS integer) AS CommentCount,
    CAST(NULL AS integer) AS UpVotes,
    CAST(NULL AS integer) AS DownVotes,
    tgh.TagName AS TagName,
    tgh.PostCount AS TagCount
  FROM TagHot tgh
)
SELECT
  cu.DisplayName AS UserDisplay,
  cu.Reputation AS UserReputation,
  th.TagName AS TopTag,
  th.PostCount AS TagPopularity,
  ra.PostId AS QuestionPostId,
  ra.Title AS QuestionTitle,
  ra.CreationDate AS QuestionCreated,
  ra.LastActivityDate AS QuestionLastActive,
  ra.Score AS QuestionScore,
  ra.ViewCount AS QuestionViews,
  ra.CommentCount AS QuestionComments,
  ra.UpVotes AS QuestionUpVotes,
  ra.DownVotes AS QuestionDownVotes,
  tu.LastActive AS LastActiveTime,
  fu2.Reputation AS ReferrerReputation,
  fu2.DisplayName AS ReferrerName
FROM Users cu
LEFT JOIN TopUsers tu ON tu.UserId = cu.Id
LEFT JOIN Posts q ON q.OwnerUserId = cu.Id AND q.PostTypeId = 1
LEFT JOIN RecentActivity ra ON ra.PostId = q.Id
LEFT JOIN (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation
  FROM Users u
) fu2 ON fu2.Id = cu.Id
LEFT JOIN TagHot th ON th.TagName = (
  SELECT tag FROM (
    SELECT trim(BOTH '<>' FROM s_tag) AS tag, row_number() OVER () AS rn
    FROM (
      SELECT unnest(string_to_array(COALESCE(q.Tags, ''), '><')) AS s_tag
    ) sub
  ) t WHERE t.rn = 1
)
WHERE cu.Id IS NOT NULL
GROUP BY
  cu.DisplayName,
  cu.Reputation,
  th.TagName,
  th.PostCount,
  ra.PostId,
  ra.Title,
  ra.CreationDate,
  ra.LastActivityDate,
  ra.Score,
  ra.ViewCount,
  ra.CommentCount,
  ra.UpVotes,
  ra.DownVotes,
  tu.LastActive,
  fu2.Reputation,
  fu2.DisplayName
ORDER BY cu.Reputation DESC, ra.LastActivityDate DESC
LIMIT 100;