-- {"query": "5573.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1346} 
WITH user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Location,
    u.AboutMe,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    COUNT(p.Id) AS PostCount,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
    AVG(v.BountyAmount) AS AvgBountyOnVotes
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id
),
recent_changes AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.Body,
    p.AcceptedAnswerId,
    p.ParentId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.LastEditorDisplayName,
    p.FavoriteCount,
    p.ClosedDate,
    p.ContentLicense,
    -- Correlated subquery: count of edits by last editor within last 30 days
    (
      SELECT COUNT(*) FROM PostHistory ph
      WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6,8,9) -- edits/updates
        AND ph.CreationDate >= current_date - INTERVAL '30 days'
    ) AS EditsLast30Days
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- questions and answers
),
linked AS (
  SELECT
    pl.Id,
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName,
    pl.CreationDate
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
),
tag_summary AS (
  SELECT
    t.TagName,
    t.Count,
    t.IsModeratorOnly,
    t.IsRequired,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
recent_votes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount,
    u.DisplayName AS VoterName
  FROM Votes v
  JOIN Users u ON u.Id = v.UserId
  WHERE v.CreationDate >= current_date - INTERVAL '7 days'
),
complex_calc AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    CASE
      WHEN p.PostTypeId = 1 THEN 'Question'
      WHEN p.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostKind,
    COALESCE(p.ViewCount, 0) * 1.0 / NULLIF(COALESCE(p.CommentCount,0) + 1, 0) AS ViewsPerComment,
    CASE
      WHEN p.Score >= 0 THEN 'Positive'
      ELSE 'Negative'
    END AS ScoreMood,
    LENGTH(p.Body) - LENGTH(REPLACE(p.Body, ' ', '')) + 1 AS WordCountBody
  FROM Posts p
),
final AS (
  SELECT
    fu.UserId,
    fu.DisplayName,
    fu.Reputation,
    fu.UserCreationDate,
    fu.LastAccessDate,
    fu.Location,
    fu.AboutMe,
    fu.Views,
    fu.UpVotes,
    fu.DownVotes,
    fu.ProfileImageUrl,
    fu.EmailHash,
    fu.AccountId,
    ua.PostCount,
    ua.AvgQuestionScore,
    ua.AvgBountyOnVotes,
    rc.PostId,
    rc.Title,
    rc.PostTypeId,
    rc.CreationDate AS PostCreationDate,
    rc.LastActivityDate AS PostLastActivityDate,
    rc.Tags,
    rc.ViewCount,
    rc.Score AS PostScore,
    rc.CommentCount,
    rc.EditsLast30Days,
    lnk.RelatedPostId,
    lnk.LinkTypeName,
    ts.TagName,
    ts.Count AS TagCount,
    rv.VoteTypeId,
    rv.CreationDate AS VoteDate,
    cv.PostId AS ClosestPostId,
    cv.CloseReason
  FROM user_activity ua
  LEFT JOIN recent_changes rc ON rc.OwnerUserId = ua.UserId
  LEFT JOIN linked lnk ON lnk.PostId = rc.PostId
  LEFT JOIN final f2 ON f2.PostId = lnk.RelatedPostId
  LEFT JOIN tag_summary ts ON ts.TagName = rc.Tags -- approximate tag link
  LEFT JOIN recent_votes rv ON rv.PostId = rc.PostId
  LEFT JOIN (
    SELECT p.Id AS PostId, ph.Comment AS CloseReason
    FROM Posts p
    JOIN PostHistory ph ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId = 10
  ) cv ON cv.PostId = rc.PostId
)
SELECT
  DISTINCT
  f.UserId,
  f.DisplayName,
  f.Reputation,
  f.UserCreationDate,
  f.LastAccessDate,
  f.Location,
  f.AboutMe,
  f.Views,
  f.UpVotes,
  f.DownVotes,
  f.ProfileImageUrl,
  f.EmailHash,
  f.AccountId,
  f.PostCount,
  f.AvgQuestionScore,
  f.AvgBountyOnVotes,
  f.PostId,
  f.Title,
  f.PostTypeId,
  f.PostCreationDate,
  f.PostLastActivityDate,
  f.Tags,
  f.ViewCount,
  f.PostScore,
  f.CommentCount,
  f.EditsLast30Days,
  f.RelatedPostId,
  f.LinkTypeName,
  f.TagName,
  f.TagCount,
  f.VoteTypeId,
  f.VoteDate,
  f.ClosestPostId,
  f.CloseReason
FROM final f
ORDER BY f.UserId, f.PostCreationDate DESC
LIMIT 100;