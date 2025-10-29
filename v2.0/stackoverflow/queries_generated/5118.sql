-- {"query": "5118.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1128} 
WITH
ActivePosts AS (
  SELECT p.Id,
         p.OwnerUserId,
         p.Title,
         p.Tags,
         p.PostTypeId,
         p.Score,
         p.ViewCount,
         p.CreationDate,
         p.LastActivityDate,
         p.CommentCount,
         p.FavoriteCount,
         p.AcceptedAnswerId,
         p.ParentId
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
),
TagInfo AS (
  SELECT t.TagName,
         t.Count,
         t.IsModeratorOnly,
         t.IsRequired,
         t.ExcerptPostId,
         t.WikiPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
UserStats AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate,
         u.LastAccessDate,
         u.Views,
         u.UpVotes,
         u.DownVotes,
         u.Location,
         u.Bio AS AboutMe          -- placeholder if actual column differs
  FROM Users u
),
RecentActivity AS (
  SELECT v.PostId,
         v.VoteTypeId,
         v.UserId AS VoterUserId,
         v.CreationDate AS VoteDate
  FROM Votes v
  WHERE v.CreateDate >= NOW() - interval '90 days'
),
PostLinksAgg AS (
  SELECT pl.PostId,
         COUNT(*) AS LinkCount,
         STRING_AGG(CASE WHEN lt.Name IS NOT NULL THEN lt.Name ELSE CAST(pl.LinkTypeId AS TEXT) END, ',') AS LinkTypes
  FROM PostLinks pl
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  GROUP BY pl.PostId
),
TopTagCooccurrence AS (
  SELECT t.TagName,
         COUNT(*) AS TagCount
  FROM (
    SELECT UNNEST(string_to_array(REPLACE(REPLACE(p.Tags, '><', ','), '<', ''), ',')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) s
  GROUP BY TagName
  ORDER BY TagCount DESC
  LIMIT 20
),
MixedBenchmark AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.PostTypeId,
    p.OwnerUserId,
    COALESCE(a.Reputation, 0) AS OwnerReputation,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScore,
    CASE
      WHEN p.OwnerUserId IS NULL THEN 'Anonymous'
      ELSE coalesce(u.DisplayName, 'Unknown')
    END AS OwnerDisplay
  FROM ActivePosts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT Id, Reputation
    FROM Users
  ) a ON a.Id = p.OwnerUserId
)
SELECT
  mp.PostId,
  mp.Title,
  mp.Score,
  mp.ViewCount,
  mp.CreationDate,
  mp.LastActivityDate,
  mp.PostTypeId,
  mp.OwnerUserId,
  mp.OwnerDisplay,
  UpV.Reputation AS OwnerReputation,
  COALESCE(p2.CommentCount, 0) AS CommentCount,
  COALESCE(p2.AnswerCount, 0) AS AnswerCount,
  COALESCE(li.LinkCount, 0) AS LinkCount,
  COALESCE(li.LinkTypes, '') AS LinkTypes,
  COALESCE(ti.TagName, '') AS MainTag,
  COALESCE(ra.RankByScore, 0) AS RankInCategory,
  STRING_AGG(DISTINCT t.TagName, ',') AS AllTags,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = mp.PostId AND v.VoteTypeId = 2) AS UpVotesLast90d,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = mp.PostId AND v.VoteTypeId = 3) AS DownVotesLast90d
FROM MixedBenchmark mp
LEFT JOIN (
  SELECT PostId, CommentCount, AnswerCount
  FROM Posts
) p2 ON mp.PostId = p2.PostId
LEFT JOIN UserStats us ON mp.OwnerUserId = us.UserId
LEFT JOIN PostLinksAgg li ON mp.PostId = li.PostId
LEFT JOIN TopTagCooccurrence ti ON TRUE
LEFT JOIN (
  SELECT p2.Id, p2.OwnerUserId
  FROM Posts p2
) t ON mp.PostId = t.Id
LEFT JOIN (
  SELECT DISTINCT unnest(string_to_array(p.Tags, '>')) AS TagName, p.Id
  FROM Posts p
  WHERE p.PostTypeId = 1
) ta ON mp.PostId = ta.Id
GROUP BY
  mp.PostId, mp.Title, mp.Score, mp.ViewCount, mp.CreationDate, mp.LastActivityDate,
  mp.PostTypeId, mp.OwnerUserId, mp.OwnerDisplay, UpV.Reputation, p2.CommentCount,
  p2.AnswerCount, li.LinkCount, li.LinkTypes, ti.TagName, ra.RankByScore, us.Reputation
ORDER BY mp.PostTypeId, RankInCategory
LIMIT 100;