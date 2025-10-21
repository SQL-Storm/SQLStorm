-- {"query": "6041.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 972} 
WITH RecentActiveQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
TagPopularity AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount,
    MAX(p.LastActivityDate) AS LastActive
  FROM Posts p
  JOIN LATERAL (
    SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) AS t ON true
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
TopTagSets AS (
  SELECT
    rp.QuestionId,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.LastActivityDate,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    pv.TagCount AS Popularity,
    pv.LastActive
  FROM RecentActiveQuestions rp
  LEFT JOIN (
    SELECT
      TagName,
      SUM(TagCount) OVER () AS TagCount, -- placeholder for window alignment
      LastActive
    FROM TagPopularity
  ) pv ON true
  ORDER BY rp.LastActivityDate DESC
),
UserStats AS (
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
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    COALESCE(b.TotalBadges, 0) AS BadgeCount
  FROM Users u
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
),
RecentVotes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount,
    w.Name AS VoteTypeName
  FROM Votes v
  JOIN VoteTypes w ON v.VoteTypeId = w.Id
  WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
),
PostEngagement AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    v.CreationDate AS LastVoteDate,
    v.VoteTypeId
  FROM Posts p
  LEFT JOIN LATERAL (
    SELECT CreationDate, VoteTypeId
    FROM Votes
    WHERE PostId = p.Id
    ORDER BY CreationDate DESC
    LIMIT 1
  ) v ON true
  WHERE p.PostTypeId IN (1,2)
),
Final AS (
  SELECT
    t.QuestionId,
    t.Title AS QuestionTitle,
    t.Tags,
    t.CreationDate AS QuestionCreated,
    t.Score AS QuestionScore,
    t.ViewCount AS QuestionViews,
    t.OwnerUserId AS QuestionOwner,
    t.LastActivityDate AS QuestionLastActivity,
    t.AnswerCount,
    t.CommentCount,
    t.FavoriteCount,
    us.UserId,
    us.DisplayName AS UserDisplayName,
    us.Reputation,
    us.CreationDate AS UserCreated,
    us.LastAccessDate AS UserLastAccess,
    ra.LastVoteDate,
    pa.VoteTypeName,
    pE.LastActivityDate AS PostLastActivity
  FROM TopTagSets t
  LEFT JOIN UserStats us ON us.UserId = t.OwnerUserId
  LEFT JOIN RecentVotes rv ON rv.PostId = t.QuestionId
  LEFT JOIN PostEngagement pE ON pE.PostId = t.QuestionId
)
SELECT
  QuestionId,
  QuestionTitle,
  Tags,
  QuestionCreated,
  QuestionScore,
  QuestionViews,
  QuestionOwner,
  QuestionLastActivity,
  AnswerCount,
  CommentCount,
  FavoriteCount,
  UserId,
  UserDisplayName,
  Reputation,
  UserCreated,
  UserLastAccess,
  LastVoteDate,
  VoteTypeName,
  PostLastActivity
FROM Final
ORDER BY QuestionLastActivity DESC
LIMIT 100;