-- {"query": "186.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1612} 
WITH
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT CASE WHEN p.Id IS NOT NULL THEN p.Id END) AS PostCount,
    SUM(CASE WHEN v.VoteTypeId IN (2, 6) THEN 1 ELSE 0 END) AS NetVotesOnOwnerPosts,
    SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCast,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCast
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
RecentActivity AS (
  SELECT
    u.Id AS UserId,
    MAX(p.LastActivityDate) AS LastActivityDate,
    MAX(p.CreationDate) AS FirstPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id
),
BadgesPerUser AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount,
    STRING_AGG(b.Name, ',') AS BadgesList
  FROM Badges b
  GROUP BY b.UserId
),
TopTagsPerUser AS (
  SELECT
    p.OwnerUserId AS UserId,
    t.TagName,
    COUNT(*) AS TagUses,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) AS rn
  FROM Posts p
  JOIN Tags t ON p.Id = t.Id /* tag-related association via Posts/Tags context */
  GROUP BY p.OwnerUserId, t.TagName
),
AggregatedTopTags AS (
  SELECT
    UserId,
    STRING_AGG(TagName, '|') FILTER (WHERE rn = 1) AS TopTagList
  FROM TopTagsPerUser
  WHERE rn = 1
  GROUP BY UserId
),
Combined AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(ua.PostCount, 0) AS PostCount,
    COALESCE(ua.NetVotesOnOwnerPosts, 0) AS NetVotesOnOwnerPosts,
    COALESCE(ua.CommentCount, 0) AS CommentCount,
    COALESCE(ua.UpVotesCast, 0) AS UpVotesCast,
    COALESCE(ua.DownVotesCast, 0) AS DownVotesCast,
    ra.LastActivityDate,
    ra.FirstPostDate,
    COALESCE(br.BadgeCount, 0) AS BadgeCount,
    br.BadgesList,
    at.TopTagList
  FROM Users u
  LEFT JOIN UserActivity ua ON ua.UserId = u.Id
  LEFT JOIN RecentActivity ra ON ra.UserId = u.Id
  LEFT JOIN BadgesPerUser br ON br.UserId = u.Id
  LEFT JOIN AggregatedTopTags at ON at.UserId = u.Id
)
SELECT
  UserId,
  DisplayName,
  Reputation,
  PostCount,
  NetVotesOnOwnerPosts,
  CommentCount,
  UpVotesCast,
  DownVotesCast,
  LastActivityDate,
  FirstPostDate,
  BadgeCount,
  BadgesList,
  TopTagList
FROM Combined
ORDER BY Reputation DESC, LastActivityDate DESC NULLS LAST
LIMIT 200;