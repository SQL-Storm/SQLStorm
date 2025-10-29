-- {"query": "5825.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1084} 
WITH 
FilteredPosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Body,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    p.ParentId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.CommunityOwnedDate,
    p.ContentLicense,
    COALESCE(p.AnswerCount, 0) AS AnswerCount
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
RecentActivity AS (
  SELECT
    f.Id,
    f.PostTypeId,
    f.OwnerUserId,
    f.Title,
    f.Tags,
    f.CreationDate,
    f.Score,
    f.ViewCount,
    f.Body,
    f.LastActivityDate,
    f.AcceptedAnswerId,
    f.ParentId,
    f.LastEditorUserId,
    f.LastEditDate,
    f.CommentCount,
    f.FavoriteCount,
    f.ClosedDate,
    f.CommunityOwnedDate,
    f.ContentLicense,
    f.AnswerCount,
    -- Window function: running total of Score over owners, partitioned by PostType
    SUM(f.Score) OVER (PARTITION BY f.PostTypeId ORDER BY f.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningScoreByType
  FROM FilteredPosts f
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC, t.TagName ASC) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
Linked AS (
  SELECT
    pl.Id,
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName,
    pl.CreationDate
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE lt.Name IN ('Linked', 'Duplicate')
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    -- Derived metric: influence score combining reputation, post count, and activity recency
    (u.Reputation * 0.6) + (COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id), 0) * 12) +
    (CASE WHEN DATEDIFF('day', u.LastAccessDate, CURRENT_TIMESTAMP) <= 7 THEN 20 ELSE 0 END) AS Influence
  FROM Users u
),
BadgesAgg AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Badges b
  GROUP BY b.UserId
),
RecentVotes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount,
    CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END AS Upvote,
    CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END AS Downvote
  FROM Votes v
  WHERE v.CreationDate > CURRENT_DATE - INTERVAL '30 days'
)
SELECT
  t.rn AS TopTagRank,
  t.TagName,
  t.Count AS TagCount,
  t.ExcerptPostId,
  t.WikiPostId,
  u.UserId AS MostActiveUserId,
  u.DisplayName AS MostActiveUserName,
  u.Reputation AS ActiveUserReputation,
  s.RunningScoreByType,
  b.GoldBadges,
  b.SilverBadges,
  b.BronzeBadges,
  a.Influence
FROM TopTags t
LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN (
  SELECT OwnerUserId AS UserId, MAX(Influence) AS Influence
  FROM UserStats
  GROUP BY UserId
) a ON a.UserId = u.UserId
LEFT JOIN Linked l ON l.PostId = p.Id
LEFT JOIN UserStats u ON u.UserId = p.OwnerUserId
LEFT JOIN BadgesAgg b ON b.UserId = p.OwnerUserId
WHERE t.rn <= 50
ORDER BY t.Count DESC, t.TagName ASC
LIMIT 50;