-- {"query": "5627.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 723} 
WITH RECURSIVE TagETests AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
RecentPosts AS (
  SELECT
    t.PostId,
    t.Title,
    t.Tags,
    t.CreationDate,
    t.OwnerUserId,
    t.rn
  FROM TagETests t
  WHERE t.rn <= 100
),
TagCombinations AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    UNNEST(string_to_array(substr(rp.Tags, 2, length(rp.Tags)-2), '><')) AS Tag
  FROM RecentPosts rp
),
TaggedUsers AS (
  SELECT
    t.PostId,
    t.Title,
    t.Tag,
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes
  FROM TagCombinations t
  LEFT JOIN Users u ON u.Id = (
    SELECT OwnerUserId FROM Posts p WHERE p.Id = t.PostId
  )
),
TopTagStats AS (
  SELECT
    Tag,
    COUNT(*) AS PostCount,
    AVG(u.Reputation) AS AvgReputation,
    MAX(u.CreationDate) AS MostRecentUserCreation
  FROM TaggedUsers tu
  LEFT JOIN Users u ON u.Id = tu.UserId
  GROUP BY Tag
),
WindowAgg AS (
  SELECT
    Tag,
    PostCount,
    AvgReputation,
    MostRecentUserCreation,
    SUM(PostCount) OVER (ORDER BY PostCount DESC ROWS BETWEEN 14 PRECEDING AND CURRENT ROW) AS Rolling14
  FROM TopTagStats
),
ComplexMetrics AS (
  SELECT
    w.Tag,
    w.PostCount,
    w.AvgReputation,
    w.MostRecentUserCreation,
    w.Rolling14,
    (w.PostCount * w.AvgReputation) AS ScoreLike
  FROM WindowAgg w
),
Final AS (
  SELECT
    c.Tag,
    c.PostCount,
    c.AvgReputation,
    c.MostRecentUserCreation,
    c.Rolling14,
    c.ScoreLike,
    (SELECT COUNT(*) FROM Posts p
     JOIN Votes v ON v.PostId = p.Id
     WHERE p.OwnerUserId IS NOT NULL
       AND v.VoteTypeId = 2
       AND p.Tags LIKE '%' || c.Tag || '%') AS UpvotesForTag
  FROM ComplexMetrics c
  ORDER BY c.Rolling14 DESC NULLS LAST
  LIMIT 50
)
SELECT
  F.Tag,
  F.PostCount,
  F.AvgReputation,
  F.MostRecentUserCreation,
  F.Rolling14,
  F.ScoreLike,
  F.UpvotesForTag,
  (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId IN (SELECT Id FROM Posts p WHERE p.OwnerUserId IS NOT NULL) AND v.VoteTypeId = 2) AS LastUpvoteDate
FROM Final F
ORDER BY F.ScoreLike DESC, F.PostCount DESC
;