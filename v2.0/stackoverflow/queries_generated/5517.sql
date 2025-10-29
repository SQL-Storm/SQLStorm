-- {"query": "5517.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 917} 
WITH latest_post_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_owner
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
),
recent_user_metrics AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    u.AccountId,
    -- compute a rolling score using window functions
    SUM(u.UpVotes - u.DownVotes) OVER (ORDER BY u.LastAccessDate ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS rolling_29d_net
  FROM Users u
),
qualified_links AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName,
    pl.CreationDate
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE lt.Id IN (1,3) -- Linked or Duplicate
),
tag_summary AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
complex_segments AS (
  SELECT
    l.Id AS LinkId,
    l.Name AS LinkName,
    v.VoteTypeId,
    v.CreationDate AS VoteDate,
    v.BountyAmount,
    u.Id AS VoterUserId
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  LEFT JOIN Users u ON v.UserId = u.Id
  WHERE vt.Id IN (2,3,10,12,16) -- UpMod, DownMod, Deletion, Spam, ModeratorReview
)
SELECT
  lp.PostId,
  rp.PostId AS RelatedPostId,
  lp.LinkTypeName,
  lp.CreationDate AS LinkCreationDate,
  p.Title AS PostTitle,
  p.Body,
  p.CreationDate AS PostCreationDate,
  p.LastActivityDate,
  p.ViewCount,
  p.Score,
  p.Tags,
  p.AnswerCount,
  p.CommentCount,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  u.LastAccessDate AS OwnerLastAccessDate,
  u.Location AS OwnerLocation,
  u.WebsiteUrl AS OwnerWebsite,
  ru.rolling_29d_net AS OwnerRollingNet29d,
  bt.Name AS BadgeName,
  b.Date AS BadgeDate,
  b.Class AS BadgeClass,
  tg.TagName AS TagRelatedName,
  ts.Count AS TagCount,
  z.LinkName AS RelatedLinkName,
  z.VoteDate AS LastVoteDate,
  z.BountyAmount
FROM latest_post_activity p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN recent_user_metrics ru ON u.Id = ru.UserId
LEFT JOIN qualified_links lp ON p.Id = lp.PostId
LEFT JOIN qualified_links rp ON lp.RelatedPostId = rp.PostId
LEFT JOIN Posts z ON rp.PostId = z.Id
LEFT JOIN Votes v ON z.Id = v.PostId
LEFT JOIN BadgeLinks bl ON u.Id = bl.UserId
LEFT JOIN Badges b ON bl.BadgeId = b.Id
LEFT JOIN (SELECT t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId FROM Tags t) tg ON tg.Id = p.OwnerUserId
LEFT JOIN TagSummary ts ON ts.TagName = ANY(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><'))
WHERE p.RN_OWNER = 1
ORDER BY p.LastActivityDate DESC
LIMIT 100;