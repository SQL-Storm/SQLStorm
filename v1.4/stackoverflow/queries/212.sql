-- {"query": "212.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 8495} 
WITH
RecentPosts AS (
  SELECT p.*
  FROM Posts p
  WHERE p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '30 days')
),
ActivePosts AS (
  SELECT p.*
  FROM Posts p
  WHERE p.LastActivityDate >= (cast('2024-10-01' as date) - INTERVAL '14 days')
),
AllPosts AS (
  SELECT * FROM RecentPosts
  UNION
  SELECT * FROM ActivePosts
),
PostStats AS (
  SELECT
    a.Id,
    a.Title,
    a.Tags,
    a.PostTypeId,
    a.Score,
    a.ViewCount,
    a.CreationDate,
    COALESCE(a.OwnerDisplayName, u.DisplayName, 'Unknown') AS OwnerDisplay,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    a.OwnerUserId,
    (SELECT COUNT(*) FROM Comments cm WHERE cm.PostId = a.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Posts pr WHERE pr.ParentId = a.Id) AS AnswerCount,
    (SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END)
     FROM Votes v WHERE v.PostId = a.Id) AS NetVotes,
    COALESCE(b.gold_badge_count, 0) AS GoldBadges,
    CASE
       WHEN a.ViewCount > 1000 THEN 'Hot'
       WHEN a.ViewCount BETWEEN 100 AND 1000 THEN 'Warm'
       ELSE 'Cold'
    END AS ViewCategory,
    (
      SELECT string_agg(t, ',')
      FROM (
        SELECT t
        FROM unnest(string_to_array(substring(a.Tags, 2, length(a.Tags) - 2), '><')) AS t
        LIMIT 5
      ) s
    ) AS TopTags,
    (array_length(string_to_array(substring(a.Tags, 2, length(a.Tags) - 2), '><'), 1)) AS TagCount
  FROM AllPosts a
  LEFT JOIN Users u ON u.Id = a.OwnerUserId
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS gold_badge_count
    FROM Badges
    WHERE Class = 1
    GROUP BY UserId
  ) b ON b.UserId = a.OwnerUserId
)
SELECT
  ps.Id,
  ps.Title,
  ps.Tags,
  ps.PostTypeId,
  ps.Score,
  ps.ViewCount,
  ps.CreationDate,
  ps.OwnerDisplay,
  ps.OwnerReputation,
  ps.CommentCount,
  ps.AnswerCount,
  ps.NetVotes,
  ps.GoldBadges,
  ps.ViewCategory,
  ps.TopTags,
  ps.TagCount,
  ROW_NUMBER() OVER (PARTITION BY ps.PostTypeId ORDER BY ps.NetVotes DESC NULLS LAST, ps.ViewCount DESC) AS PostRank
FROM PostStats ps
ORDER BY PostRank
LIMIT 100;