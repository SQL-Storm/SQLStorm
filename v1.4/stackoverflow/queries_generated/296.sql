-- {"query": "296.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 8725} 
WITH
high_score AS (
  SELECT
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COALESCE(gb.GoldCount, 0) AS GoldBadges,
    COALESCE(ap.AnswerCount, 0) AS AnswerCount,
    COALESCE(lp.LinkCount, 0) AS LinkCount,
    COALESCE(tp.TagCount, 0) AS TagCount,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST) AS rn
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
     SELECT UserId, COUNT(*) AS GoldCount
     FROM Badges
     WHERE Class = 1
     GROUP BY UserId
  ) gb ON gb.UserId = u.Id
  LEFT JOIN (
     SELECT PostId, COUNT(*) AS AnswerCount
     FROM Posts
     WHERE PostTypeId = 2
     GROUP BY PostId
  ) ap ON ap.PostId = p.Id
  LEFT JOIN (
     SELECT PostId, COUNT(*) AS LinkCount
     FROM PostLinks
     GROUP BY PostId
  ) lp ON lp.PostId = p.Id
  LEFT JOIN (
     SELECT Id AS PostId,
            COALESCE(array_length(string_to_array(substr(Tags, 2, length(Tags)-2), '><'), 1), 0) AS TagCount
     FROM Posts
  ) tp ON tp.PostId = p.Id
  WHERE p.PostTypeId = 1
),
high_view AS (
  SELECT
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COALESCE(gb.GoldCount, 0) AS GoldBadges,
    COALESCE(ap.AnswerCount, 0) AS AnswerCount,
    COALESCE(lp.LinkCount, 0) AS LinkCount,
    COALESCE(tp.TagCount, 0) AS TagCount,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC NULLS LAST, p.Score DESC NULLS LAST) AS rn
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
     SELECT UserId, COUNT(*) AS GoldCount
     FROM Badges
     WHERE Class = 1
     GROUP BY UserId
  ) gb ON gb.UserId = u.Id
  LEFT JOIN (
     SELECT PostId, COUNT(*) AS AnswerCount
     FROM Posts
     WHERE PostTypeId = 2
     GROUP BY PostId
  ) ap ON ap.PostId = p.Id
  LEFT JOIN (
     SELECT PostId, COUNT(*) AS LinkCount
     FROM PostLinks
     GROUP BY PostId
  ) lp ON lp.PostId = p.Id
  LEFT JOIN (
     SELECT Id AS PostId,
            COALESCE(array_length(string_to_array(substr(Tags, 2, length(Tags)-2), '><'), 1), 0) AS TagCount
     FROM Posts
  ) tp ON tp.PostId = p.Id
  WHERE p.PostTypeId = 1
)
SELECT
  hs.Id AS PostId,
  hs.Title,
  hs.Score,
  hs.ViewCount,
  hs.CreationDate,
  hs.OwnerUserId,
  hs.OwnerDisplayName,
  hs.Reputation,
  hs.LastAccessDate,
  hs.Views,
  hs.UpVotes,
  hs.DownVotes,
  hs.GoldBadges,
  hs.AnswerCount,
  hs.LinkCount,
  hs.TagCount,
  hs.rn,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = hs.Id AND v.VoteTypeId = 2) AS UpModCount
FROM high_score hs
WHERE hs.rn <= 100

UNION ALL

SELECT
  hv.Id AS PostId,
  hv.Title,
  hv.Score,
  hv.ViewCount,
  hv.CreationDate,
  hv.OwnerUserId,
  hv.OwnerDisplayName,
  hv.Reputation,
  hv.LastAccessDate,
  hv.Views,
  hv.UpVotes,
  hv.DownVotes,
  hv.GoldBadges,
  hv.AnswerCount,
  hv.LinkCount,
  hv.TagCount,
  hv.rn,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = hv.Id AND v.VoteTypeId = 2) AS UpModCount
FROM high_view hv
WHERE hv.rn <= 100
ORDER BY PostId;