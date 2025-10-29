-- {"query": "5287.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 926} 
WITH top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn_loc
  FROM Users u
),
recent_posts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Body,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastActivityDate,
    p.CommentCount,
    p.FavoriteCount,
    p.OwnerDisplayName
  FROM Posts p
  WHERE p.CreationDate >= now() - INTERVAL '180 days'
    AND p.PostTypeId IN (1,2) -- Questions and Answers
),
tag_aggregate AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    COUNT(p.Id) AS PostsWithTag
  FROM Tags t
  JOIN Posts p ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
  WHERE t.IsModeratorOnly = 0
  GROUP BY t.TagName, t.Count
),
complex_filter AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount
  FROM Votes v
  WHERE v.VoteTypeId IN (2,3,14,16) -- UpMod, DownMod, NominateModerator, ModeratorReview
    OR (v.VoteTypeId = 10 AND v.BountyAmount IS NOT NULL)
),
joined AS (
  SELECT
    tp.PostId,
    tp.OwnerUserId,
    tp.Title,
    tp.CreationDate AS PostCreation,
    tp.LastActivityDate,
    tp.Score,
    tp.ViewCount,
    tp.Tags,
    CASE
      WHEN tp.AcceptedAnswerId IS NOT NULL THEN 1
      ELSE 0
    END AS HasAcceptedAnswer,
    cu.DisplayName AS LastEditor,
    cu.Reputation AS EditorReputation,
    r.Location AS EditorLocation
  FROM recent_posts tp
  LEFT JOIN Users cu ON tp.OwnerUserId = cu.Id
  LEFT JOIN Users r ON cu.Id = r.Id
  LEFT JOIN (
    SELECT DISTINCT UserId, MAX(CreationDate) AS maxdate
    FROM Votes
    GROUP BY UserId
  ) v ON cu.Id = v.UserId
)
SELECT
  u.UserId,
  u.DisplayName AS UserDisplayName,
  u.Reputation AS UserReputation,
  u.CreationDate AS UserCreationDate,
  u.LastAccessDate AS UserLastAccess,
  u.Location AS UserLocation,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  u.AccountId,
  (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS PostCount,
  (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id) AS AvgPostScore,
  (SELECT MAX(p.LastActivityDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastActivePostDate,
  ta.TagName AS TopTag,
  ta.TagCount AS TagPopularity,
  ta.PostsWithTag AS PostsWithTopTag,
  (SELECT STRING_AGG(CONCAT('Post ', PostId, '->', Title), ';') FROM joined j WHERE j.OwnerUserId = u.Id) AS SamplePostTitles,
  (SELECT MAX(PostCreation) FROM joined j WHERE j.OwnerUserId = u.Id) AS MostRecentPostDate
FROM top_users u
LEFT JOIN (
  SELECT
    Id AS UserId,
    MAX(Score) AS MaxScore
  FROM Posts
  GROUP BY Id
) pmax ON pmax.UserId = u.Id
LEFT JOIN tag_aggregate ta ON ta.TagName = (SELECT TOP 1 TagName FROM Tags t WHERE t.TagName IS NOT NULL LIMIT 1)
LEFT JOIN complex_filter cf ON cf.PostId = pmax.UserId
ORDER BY u.Reputation DESC, u.LastAccessDate DESC
LIMIT 100;