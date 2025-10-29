-- {"query": "5662.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 761} 
WITH
RecentlyActivePosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.OwnerDisplayName,
    p.LastEditorUserId,
    p.LastEditorDisplayName,
    p.Body,
    p.ContentLicense
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '90 days'
),
TopTags AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag
  FROM RecentlyActivePosts p
),
TagStats AS (
  SELECT
    Tag AS TagName,
    COUNT(*) AS PostCount,
    SUM(p.ViewCount) AS TotalViews,
    AVG(p.Score) AS AvgScore
  FROM RecentlyActivePosts p
  JOIN TopTags t ON t.Tag = ANY(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><'))
  GROUP BY Tag
),
BadgeActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName AS DisplayName,
    COUNT(b.Id) AS BadgesEarned,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
RecentVotes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount
  FROM Votes v
  WHERE v.CreationDate >= NOW() - INTERVAL '30 days'
),
CorrelatedActivity AS (
  SELECT
    rp.Id AS PostId,
    rp.Title,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.LastActivityDate,
    rp.ViewCount,
    rp.Score,
    rp.AnswerCount,
    COALESCE(ba.BadgesEarned, 0) AS BadgesEarnedLast90,
    COALESCE(vs.TotalVotes, 0) AS TotalVotesLast30
  FROM RecentlyActivePosts rp
  LEFT JOIN BadgeActivity ba ON ba.UserId = rp.OwnerUserId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS TotalVotes
    FROM RecentVotes
    GROUP BY PostId
  ) vs ON vs.PostId = rp.Id
)
SELECT
  ca.PostId,
  ca.Title,
  ca.OwnerUserId,
  ca.OwnerDisplayName,
  ca.LastActivityDate,
  ca.ViewCount,
  ca.Score,
  ca.AnswerCount,
  ca.BadgesEarnedLast90,
  ca.TotalVotesLast30,
  ts.TagName,
  ts.PostCount AS PostsWithTagInLast90,
  ts.TotalViews AS ViewsForTagInLast90,
  ts.AvgScore AS AvgScoreForTag
FROM CorrelatedActivity ca
LEFT JOIN TagStats ts
  ON ts.TagName = ANY(string_to_array(substr(ca.Title, 2, length(ca.Title)-2), '><'))
ORDER BY ca.LastActivityDate DESC
LIMIT 100;