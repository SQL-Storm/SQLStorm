-- {"query": "5810.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 814}
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
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
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
  WHERE u.AccountId IS NOT NULL
),
PopularTagWikis AS (
  SELECT
    t.Id AS TagWikiId,
    t.TagName,
    t.Count,
    t.WikiPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE AND t.IsRequired = FALSE
),
PostTagActivity AS (
  SELECT
    p.Id AS PostId,
    tag.TagName,
    COUNT(*) AS TagUsage
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT TRIM(x) AS TagName
    FROM (
      SELECT regexp_split_to_table(substr(p.Tags, 2, length(p.Tags)-2), '><') AS x
    ) s
  ) tag
  GROUP BY p.Id, tag.TagName
),
CorrelatedStats AS (
  SELECT
    r.PostId,
    r.Title,
    r.OwnerUserId,
    r.CreationDate AS PostCreationDate,
    r.LastActivityDate,
    r.Score,
    r.ViewCount,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    pv.TagName,
    pv.TagUsage
  FROM RecentActivePosts r
  LEFT JOIN TopUsers u ON r.OwnerUserId = u.UserId
  LEFT JOIN (
    SELECT
      p.Id AS PostId,
      tag.TagName,
      COUNT(*) AS TagUsage
    FROM Posts p
    CROSS JOIN LATERAL (
      SELECT regexp_split_to_table(substr(p.Tags, 2, length(p.Tags)-2), '><') AS TagName
    ) tag
    GROUP BY p.Id, tag.TagName
  ) pv ON r.PostId = pv.PostId
),
WindowedStats AS (
  SELECT
    cs.PostId,
    cs.Title,
    cs.OwnerUserId,
    cs.PostCreationDate,
    cs.LastActivityDate,
    cs.Score,
    cs.ViewCount,
    cs.OwnerDisplayName,
    cs.Reputation,
    cs.TagName,
    cs.TagUsage,
    ROW_NUMBER() OVER (PARTITION BY cs.TagName ORDER BY cs.Score DESC, cs.LastActivityDate DESC) AS rn_by_tag
  FROM CorrelatedStats cs
  WHERE cs.TagName IS NOT NULL
),
FinalAgg AS (
  SELECT
    ws.TagName,
    MAX(ws.Score) AS MaxScoreForTag,
    AVG(ws.Reputation) AS AvgAuthorReputation,
    SUM(ws.TagUsage) AS TotalTagAssociations,
    COUNT(*) AS PostsConsidered
  FROM WindowedStats ws
  GROUP BY ws.TagName
)
SELECT
  fa.TagName,
  fa.MaxScoreForTag,
  fa.AvgAuthorReputation,
  fa.TotalTagAssociations,
  fa.PostsConsidered,
  (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1) AS TotalQuestions,
  (SELECT COUNT(*) FROM Votes v WHERE v.VoteTypeId = 2) AS TotalUpvotes,
  (SELECT COUNT(*) FROM Votes v WHERE v.VoteTypeId = 3) AS TotalDownvotes
FROM FinalAgg fa
ORDER BY fa.TotalTagAssociations DESC, fa.MaxScoreForTag DESC
LIMIT 100;