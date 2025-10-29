-- {"query": "5975.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 993} 
WITH
FilteredPosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    p.Body,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.OwnerDisplayName,
    p.LastEditorDisplayName
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- questions and answers
),
LastActivityPerPost AS (
  SELECT
    fp.Id,
    fp.Title,
    fp.OwnerUserId,
    fp.CreationDate,
    fp.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY fp.OwnerUserId ORDER BY fp.LastActivityDate DESC) AS rn
  FROM FilteredPosts fp
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.Location,
    u.EmailHash,
    COALESCE(bg.GoldBadges, 0) AS GoldBadges,
    COALESCE(bs.SilverBadges, 0) AS SilverBadges,
    COALESCE(bb.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(wv.TotalViews, 0) AS TotalPostViews
  FROM Users u
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS GoldBadges
    FROM Badges
    WHERE Class = 1
    GROUP BY UserId
  ) bg ON bg.UserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS SilverBadges
    FROM Badges
    WHERE Class = 2
    GROUP BY UserId
  ) bs ON bs.UserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS BronzeBadges
    FROM Badges
    WHERE Class = 3
    GROUP BY UserId
  ) bb ON bb.UserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId, SUM(ViewCount) AS TotalViews
    FROM Posts
    GROUP BY OwnerUserId
  ) wv ON wv.OwnerUserId = u.Id
  WHERE u.Id IN (SELECT DISTINCT OwnerUserId FROM FilteredPosts WHERE OwnerUserId IS NOT NULL)
),
ComplexQuery AS (
  SELECT
    u.UserId,
    u.DisplayName AS UserDisplayName,
    u.Reputation,
    up.Title AS UserPostTitle,
    up.LastActivityDate,
    up.LastEditorDisplayName,
    up.Score,
    up.ViewCount,
    up.Tags,
    up.Body,
    up.ContentLicense,
    EXISTS (
      SELECT 1
      FROM Votes v
      WHERE v.UserId = u.UserId AND v.PostId = up.Id AND v.VoteTypeId = 2
        AND v.CreationDate >= up.CreationDate
    ) AS HasUpvotedAfterCreation,
    CASE
      WHEN up.PostTypeId = 1 THEN 'Question'
      WHEN up.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostKind
  FROM UserStats u
  JOIN LastActivityPerPost up
    ON up.OwnerUserId = u.UserId
  WHERE up.rn = 1
    AND up.LastActivityDate IS NOT NULL
),
TemporalCTE AS (
  SELECT
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.UserId) AS PostCountByUser,
    (SELECT MAX(CreationDate) FROM Posts p3 WHERE p3.OwnerUserId = u.UserId) AS LastPostDate
  FROM Users u
  JOIN LastActivityPerPost l ON l.OwnerUserId = u.Id
  GROUP BY u.Id
)
SELECT
  cq.UserId,
  cq.UserDisplayName,
  cq.Reputation,
  cq.UserPostTitle,
  cq.LastActivityDate,
  cq.LastEditorDisplayName,
  cq.Score,
  cq.ViewCount,
  cq.Tags,
  cq.Body,
  cq.ContentLicense,
  cq.HasUpvotedAfterCreation,
  cq.PostKind,
  t.PostCountByUser,
  t.LastPostDate
FROM ComplexQuery cq
JOIN TemporalCTE t ON t.LastPostDate = cq.LastActivityDate
ORDER BY cq.LastActivityDate DESC
LIMIT 100;