-- {"query": "5786.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 933}
WITH 
RecentPosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    p.LastEditDate,
    p.AcceptedAnswerId,
    p.ParentId
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
),
TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl
  FROM Users u
  WHERE u.Reputation > 1000
),
TagStats AS (
  SELECT
    unnest(string_to_array(p.Tags, '>')) AS tag_raw
  FROM RecentPosts p
  WHERE p.Tags IS NOT NULL
),
TagClean AS (
  SELECT
    TRIM(BOTH ' <>' FROM tag_raw) AS TagName
  FROM TagStats
  WHERE tag_raw ~ '^[^<>]+$'
),
TagCounts AS (
  SELECT
    TagName,
    COUNT(*) AS PostCount
  FROM TagClean
  GROUP BY TagName
),
Keyboard AS (
  SELECT
    r.Id,
    r.Title,
    r.CreationDate,
    r.OwnerUserId,
    r.ViewCount,
    r.Score,
    r.AnswerCount,
    COALESCE(vt.Name, 'Unknown') AS LastVoteType,
    COALESCE((
      SELECT STRING_AGG(vt2.Name || ':' || CAST(vsub.BountyAmount AS VARCHAR), ',')
      FROM Votes vsub
      JOIN VoteTypes vt2 ON vsub.VoteTypeId = vt2.Id
      WHERE vsub.PostId = r.Id
        AND vsub.CreationDate > COALESCE(r.LastEditDate, r.CreationDate) - INTERVAL '7' DAY
    ), '') AS RecentVotesSummary,
    (
      SELECT COUNT(*) 
      FROM PostLinks pl
      WHERE pl.PostId = r.Id
    ) AS LinkCount
  FROM RecentPosts r
  LEFT JOIN Votes v ON v.PostId = r.Id
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
),
ComplexFilters AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.Tags,
    p.PostTypeId,
    p.AcceptedAnswerId,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id) AS LinkCount,
    (SELECT STRING_AGG(COALESCE(u.DisplayName, u2.DisplayName), ',')
     FROM Votes v
     JOIN Users u ON v.UserId = u.Id
     LEFT JOIN Users u2 ON p.OwnerUserId = u2.Id
     WHERE v.PostId = p.Id) AS VoterNames
  FROM Posts p
  WHERE p.PostTypeId IN (1,2)
    AND p.LastActivityDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '15' DAY
)
SELECT
  cp.Id AS PostId,
  cp.Title,
  cp.OwnerUserId,
  COALESCE(ru.DisplayName, ru.DisplayName) AS OwnerDisplayName,
  cp.CreationDate,
  cp.LastActivityDate,
  cp.Score,
  cp.ViewCount,
  cp.AnswerCount,
  cp.CommentCount,
  cp.Tags,
  pt.Name AS PostType,
  ai.Title AS AcceptedAnswerInfo,
  cl.Name AS CloseReason,
  tc.PostCount AS TagUsageInRecentPosts,
  ru.Reputation AS OwnerReputation,
  ku.RecentVotesSummary,
  ku.LinkCount AS TotalLinksFromPost
FROM ComplexFilters cp
LEFT JOIN PostTypes pt ON cp.PostTypeId = pt.Id
LEFT JOIN Posts ai ON cp.AcceptedAnswerId = ai.Id
LEFT JOIN CloseReasonTypes cl ON cl.Id IS NOT NULL
LEFT JOIN TopUsers ru ON cp.OwnerUserId = ru.UserId
LEFT JOIN TagCounts tc ON cp.Tags IS NOT NULL
LEFT JOIN Keyboard ku ON ku.Id = cp.Id
GROUP BY
  cp.Id,
  cp.Title,
  cp.OwnerUserId,
  ru.DisplayName,
  cp.CreationDate,
  cp.LastActivityDate,
  cp.Score,
  cp.ViewCount,
  cp.AnswerCount,
  cp.CommentCount,
  cp.Tags,
  pt.Name,
  ai.Title,
  cl.Name,
  tc.PostCount,
  ru.Reputation,
  ku.RecentVotesSummary,
  ku.LinkCount
ORDER BY cp.LastActivityDate DESC
LIMIT 100;