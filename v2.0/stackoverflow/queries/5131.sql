-- {"query": "5131.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1097} 
WITH
RecentTopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    p.LastEditDate,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
),
TopQuestionTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS NumQuestions,
    AVG(q.Score) AS AvgScore,
    MAX(q.ViewCount) AS MaxViews
  FROM RecentTopPosts q
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substr(q.Tags, 2, length(q.Tags)-2), '><')) AS TagName
  ) AS t
  GROUP BY t.TagName
),
ActiveUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.UpVotes,
    u.DownVotes,
    u.Views
  FROM Users u
  WHERE u.LastAccessDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
),
UserBadges AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
  FROM Badges b
  GROUP BY b.UserId
),
CommentActivity AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCount,
    MAX(c.CreationDate) AS LastCommentDate
  FROM Comments c
  GROUP BY c.PostId
),
PostLinksAgg AS (
  SELECT
    pl.PostId,
    COUNT(*) AS LinkCount,
    SUM(CASE WHEN lt.Name ILIKE '%duplicate%' THEN 1 ELSE 0 END) AS DuplicateLinks
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  GROUP BY pl.PostId
),
VotesAgg AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN vt.Name ILIKE 'Up%' THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN vt.Name ILIKE 'Down%' THEN 1 ELSE 0 END) AS DownVotes,
    SUM(v.BountyAmount) AS TotalBounty
  FROM Votes v
  JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  GROUP BY v.PostId
),
FullQuery AS (
  SELECT
    q.PostId,
    q.Title,
    q.Tags,
    q.Score,
    q.ViewCount,
    q.CreationDate,
    q.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    COALESCE(cb.BadgeCount, 0) AS BadgeCount,
    COALESCE(ab.GoldBadges, 0) AS GoldBadges,
    COALESCE(cc.CommentCount, 0) AS CommentCount,
    COALESCE(PL.LinkCount, 0) AS LinkCount,
    COALESCE(va.UpVotes, 0) AS UpVotes,
    COALESCE(va.DownVotes, 0) AS DownVotes,
    COALESCE(va.TotalBounty, 0) AS BountyTotal,
    q.LastActivityDate,
    q.LastEditDate,
    au.Reputation,
    au.LastAccessDate
  FROM RecentTopPosts q
  JOIN Users u ON u.Id = q.OwnerUserId
  LEFT JOIN ActiveUsers au ON au.UserId = q.OwnerUserId
  LEFT JOIN UserBadges cb ON cb.UserId = q.OwnerUserId
  LEFT JOIN (SELECT UserId, GoldBadges, BadgeCount FROM UserBadges) ab ON ab.UserId = q.OwnerUserId
  LEFT JOIN CommentActivity cc ON cc.PostId = q.PostId
  LEFT JOIN PostLinksAgg PL ON PL.PostId = q.PostId
  LEFT JOIN VotesAgg va ON va.PostId = q.PostId
  WHERE q.rn = 1 OR q.rn = 2
),
FinalRollup AS (
  SELECT
    ft.TagName,
    SUM(ft.NumQuestions) AS TotalQuestions,
    AVG(ft.AvgScore) AS AvgQuestionScore,
    MAX(ft.MaxViews) AS PeakViews
  FROM TopQuestionTags ft
  GROUP BY ft.TagName
)
SELECT
  fr.PostId,
  fr.Title,
  fr.Tags,
  fr.Score,
  fr.ViewCount,
  fr.CreationDate,
  fr.OwnerDisplayName,
  fr.LastActivityDate,
  fr.LastEditDate,
  fr.Reputation AS OwnerReputation,
  fr.CommentCount,
  fr.LinkCount,
  fr.UpVotes,
  fr.DownVotes,
  fr.BountyTotal
FROM FullQuery fr
JOIN PostTypes pt ON pt.Id = 1
ORDER BY fr.LastActivityDate DESC, fr.Score DESC
LIMIT 200;