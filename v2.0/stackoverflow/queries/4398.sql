-- {"query": "4398.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2455} 
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ph.Comment,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM
      PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edits to Title, Body, or Tags
  ),
  LatestPostInfo AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.Tags,
      p.AnswerCount,
      p.FavoriteCount,
      p.ClosedDate,
      p.CommunityOwnedDate,
      MAX(ph.CreationDate) AS LastEditDate
    FROM
      Posts p
    LEFT JOIN
      PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.Title,
      p.Tags,
      p.AnswerCount,
      p.FavoriteCount,
      p.ClosedDate,
      p.CommunityOwnedDate
  ),
  UserPostContribution AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS TotalPostsOwned,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
      AVG(p.Score) AS AvgPostScore,
      SUM(p.ViewCount) AS TotalViews
    FROM
      Posts p
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY
      p.OwnerUserId
  ),
  CommentActivity AS (
    SELECT
      c.PostId,
      COUNT(c.Id) AS CommentCountOnPost,
      MAX(c.CreationDate) AS LastCommentDate
    FROM
      Comments c
    GROUP BY
      c.PostId
  ),
  PostLinkAnalysis AS (
    SELECT
      pl.PostId,
      COUNT(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE NULL END) AS DuplicateLinkCount,
      COUNT(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE NULL END) AS LinkedPostCount
    FROM
      PostLinks pl
    GROUP BY
      pl.PostId
  )
SELECT
  u.DisplayName AS OwnerDisplayName,
  lpi.Title AS PostTitle,
  lpi.Tags AS PostTags,
  COALESCE(upc.TotalQuestionsOwned, 0) AS UserTotalQuestions,
  COALESCE(upc.TotalAnswersOwned, 0) AS UserTotalAnswers,
  COALESCE(upc.AvgPostScore, 0.0) AS UserAvgScore,
  COALESCE(upc.TotalViews, 0) AS UserTotalViews,
  lpi.AnswerCount AS PostAnswerCount,
  lpi.FavoriteCount AS PostFavoriteCount,
  CASE
    WHEN lpi.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN lpi.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  COALESCE(ca.CommentCountOnPost, 0) AS PostCommentCount,
  DATE_PART('day', cast('2024-10-01 12:34:56' as timestamp) - lpi.LastEditDate) AS DaysSinceLastEdit,
  COALESCE(pla.DuplicateLinkCount, 0) AS PostDuplicateLinks,
  COALESCE(pla.LinkedPostCount, 0) AS PostLinkedToCount,
  -- Complex predicate with string manipulation and NULL logic
  CASE
    WHEN lpi.Title LIKE '%[^a-zA-Z0-9 ]%' AND lpi.Tags IS NOT NULL AND LENGTH(lpi.Tags) > 10 THEN 'Potentially Malformed Title/Long Tags'
    WHEN lpi.CommunityOwnedDate IS NULL AND lpi.ClosedDate IS NOT NULL AND ABS(EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - lpi.ClosedDate)) / (60 * 60 * 24)) > 365 THEN 'Old Closed Post'
    ELSE 'Standard'
  END AS PostCharacteristic,
  -- Correlated subquery for specific edit details
  (
    SELECT
      COUNT(*)
    FROM
      PostHistory ph_sub
    WHERE
      ph_sub.PostId = lpi.PostId
      AND ph_sub.PostHistoryTypeId = 2 -- Initial Body
      AND ph_sub.UserId = lpi.OwnerUserId
      AND ph_sub.CreationDate < lpi.LastEditDate
  ) AS OriginalBodyEditsByOwner
FROM
  Users u
JOIN
  LatestPostInfo lpi ON u.Id = lpi.OwnerUserId
LEFT JOIN
  UserPostContribution upc ON u.Id = upc.OwnerUserId
LEFT JOIN
  CommentActivity ca ON lpi.PostId = ca.PostId
LEFT JOIN
  PostLinkAnalysis pla ON lpi.PostId = pla.PostId
WHERE
  lpi.AnswerCount > 5 OR lpi.FavoriteCount > 10
UNION
SELECT
  'Community' AS OwnerDisplayName,
  lpi.Title AS PostTitle,
  lpi.Tags AS PostTags,
  COALESCE(upc.TotalQuestionsOwned, 0) AS UserTotalQuestions,
  COALESCE(upc.TotalAnswersOwned, 0) AS UserTotalAnswers,
  COALESCE(upc.AvgPostScore, 0.0) AS UserAvgScore,
  COALESCE(upc.TotalViews, 0) AS UserTotalViews,
  lpi.AnswerCount AS PostAnswerCount,
  lpi.FavoriteCount AS PostFavoriteCount,
  CASE
    WHEN lpi.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN lpi.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  COALESCE(ca.CommentCountOnPost, 0) AS PostCommentCount,
  DATE_PART('day', cast('2024-10-01 12:34:56' as timestamp) - lpi.LastEditDate) AS DaysSinceLastEdit,
  COALESCE(pla.DuplicateLinkCount, 0) AS PostDuplicateLinks,
  COALESCE(pla.LinkedPostCount, 0) AS PostLinkedToCount,
  CASE
    WHEN lpi.Title LIKE '%[^a-zA-Z0-9 ]%' AND lpi.Tags IS NOT NULL AND LENGTH(lpi.Tags) > 10 THEN 'Potentially Malformed Title/Long Tags'
    WHEN lpi.CommunityOwnedDate IS NULL AND lpi.ClosedDate IS NOT NULL AND ABS(EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - lpi.ClosedDate)) / (60 * 60 * 24)) > 365 THEN 'Old Closed Post'
    ELSE 'Standard'
  END AS PostCharacteristic,
  (
    SELECT
      COUNT(*)
    FROM
      PostHistory ph_sub
    WHERE
      ph_sub.PostId = lpi.PostId
      AND ph_sub.PostHistoryTypeId = 2 -- Initial Body
      AND ph_sub.UserId = -1 -- Community User ID
      AND ph_sub.CreationDate < lpi.LastEditDate
  ) AS OriginalBodyEditsByOwner
FROM
  Users u
JOIN
  LatestPostInfo lpi ON u.Id = lpi.OwnerUserId
LEFT JOIN
  UserPostContribution upc ON u.Id = upc.OwnerUserId
LEFT JOIN
  CommentActivity ca ON lpi.PostId = ca.PostId
LEFT JOIN
  PostLinkAnalysis pla ON lpi.PostId = pla.PostId
WHERE
  lpi.CommunityOwnedDate IS NOT NULL
UNION
SELECT
  'ModeratorNominee' AS OwnerDisplayName,
  lpi.Title AS PostTitle,
  lpi.Tags AS PostTags,
  COALESCE(upc.TotalQuestionsOwned, 0) AS UserTotalQuestions,
  COALESCE(upc.TotalAnswersOwned, 0) AS UserTotalAnswers,
  COALESCE(upc.AvgPostScore, 0.0) AS UserAvgScore,
  COALESCE(upc.TotalViews, 0) AS UserTotalViews,
  lpi.AnswerCount AS PostAnswerCount,
  lpi.FavoriteCount AS PostFavoriteCount,
  CASE
    WHEN lpi.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN lpi.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  COALESCE(ca.CommentCountOnPost, 0) AS PostCommentCount,
  DATE_PART('day', cast('2024-10-01 12:34:56' as timestamp) - lpi.LastEditDate) AS DaysSinceLastEdit,
  COALESCE(pla.DuplicateLinkCount, 0) AS PostDuplicateLinks,
  COALESCE(pla.LinkedPostCount, 0) AS PostLinkedToCount,
  CASE
    WHEN lpi.Title LIKE '%[^a-zA-Z0-9 ]%' AND lpi.Tags IS NOT NULL AND LENGTH(lpi.Tags) > 10 THEN 'Potentially Malformed Title/Long Tags'
    WHEN lpi.CommunityOwnedDate IS NULL AND lpi.ClosedDate IS NOT NULL AND ABS(EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - lpi.ClosedDate)) / (60 * 60 * 24)) > 365 THEN 'Old Closed Post'
    ELSE 'Standard'
  END AS PostCharacteristic,
  (
    SELECT
      COUNT(*)
    FROM
      PostHistory ph_sub
    WHERE
      ph_sub.PostId = lpi.PostId
      AND ph_sub.PostHistoryTypeId = 6 -- Moderator Nomination
      AND ph_sub.UserId = lpi.OwnerUserId
      AND ph_sub.CreationDate < lpi.LastEditDate
  ) AS OriginalBodyEditsByOwner
FROM
  Users u
JOIN
  LatestPostInfo lpi ON u.Id = lpi.OwnerUserId
LEFT JOIN
  UserPostContribution upc ON u.Id = upc.OwnerUserId
LEFT JOIN
  CommentActivity ca ON lpi.PostId = ca.PostId
LEFT JOIN
  PostLinkAnalysis pla ON lpi.PostId = pla.PostId
WHERE
  EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = lpi.PostId AND v.VoteTypeId = 14)
ORDER BY
  UserTotalAnswers DESC, PostFavoriteCount DESC;