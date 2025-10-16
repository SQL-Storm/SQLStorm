-- {"query": "6057.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1206} 
WITH TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
),
TagBadges AS (
  SELECT
    b.UserId,
    b.Name AS BadgeName,
    b.Date AS EarnedDate,
    b.Class,
    b.TagBased,
    ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn
  FROM Badges b
  WHERE b.TagBased = 1
),
PostStats AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.CreationDate,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    p.OwnerDisplayName,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.FavoriteCount,
    p.ContentLicense,
    COALESCE(p.CloseReason, NULL) AS CloseReasonGuess
  FROM Posts p
),
RecentActivity AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId AS VoterId,
    v.CreationDate AS VoteDate,
    vt.Name AS VoteTypeName,
    v.BountyAmount
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
),
LinkedPosts AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE lt.Id IN (1,3) -- focus on Linked and Duplicate
),
TagSearch AS (
  SELECT
    t.TagName,
    t.Count,
    t.IsModeratorOnly,
    t.IsRequired
  FROM Tags t
  WHERE t.TagName IS NOT NULL
),
AggStats AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
  FROM Tags t
  LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%' 
  GROUP BY t.TagName
),
ComplexQuery AS (
  SELECT
    u.UserId,
    u.DisplayName AS UserDisplayName,
    p.PostId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.CreationDate AS PostCreationDate,
    pa.EarnedDate AS BadgeEarnedDate,
    rb.RelatedPostId,
    lt.Name AS LinkTypeName,
    vt.Name AS VoteTypeName,
    ra.Score AS LastPostScore,
    CASE
      WHEN p.OwnerUserId IS NULL THEN 'Anonymous'
      ELSE p.OwnerDisplayName
    END AS EffectiveDisplayName,
    CASE
      WHEN p.PostTypeId = 1 THEN 'Question'
      WHEN p.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostTypeLabel
  FROM TopUsers u
  LEFT JOIN PostStats p ON p.OwnerUserId = u.UserId
  LEFT JOIN RecentActivity ra
    ON ra.PostId = p.PostId
  LEFT JOIN TagBadges pa ON pa.UserId = u.UserId AND pa.rn = 1
  LEFT JOIN LinkedPosts rb ON rb.PostId = p.PostId
  LEFT JOIN TagSearch ts ON ts.TagName = REGEXP_REPLACE(p.Tags, '[<>]', '', 'g')
  LEFT JOIN Tags t ON t.TagName SIMILAR TO REGEXP_REPLACE(p.Tags, '[<>]', '', 'g')
  LEFT JOIN Votes v ON v.PostId = p.PostId
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  LEFT JOIN Posts pr ON pr.Id = p.ParentId
  WHERE
    u.Reputation > 1000
    AND p.Score > 0
    AND p.ViewCount > 50
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
    AND (REGEXP_LIKE(p.Title, '(?i)benchmark|performance|stress') OR REGEXP_LIKE(p.Tags, '(?i)benchmark|performance'))
  ORDER BY u.Reputation DESC, p.CreationDate DESC
  FETCH FIRST 100 ROWS ONLY
)
SELECT
  CU.UserId,
  CU.DisplayName AS UserDisplayName,
  CU.PostId,
  CU.Title,
  CU.Tags,
  CU.Score,
  CU.ViewCount,
  CU.CommentCount,
  CU.AnswerCount,
  CU.PostCreationDate,
  CU.BadgeEarnedDate,
  CU.RelatedPostId,
  CU.LinkTypeName,
  CU.VoteTypeName,
  CU.LastPostScore,
  CU.EffectiveDisplayName,
  CU.PostTypeLabel
FROM ComplexQuery CU
LEFT JOIN Posts PR ON PR.Id = CU.PostId
LEFT JOIN Badges B ON B.UserId = CU.UserId AND B.Date = CU.BadgeEarnedDate
ORDER BY CU.UserId, CU.PostCreationDate DESC;