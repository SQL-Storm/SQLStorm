-- {"query": "5368.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1062}
WITH notable_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.FavoriteCount,
    p.CommentCount,
    p.AcceptedAnswerId,
    p.ParentId,
    p.ContentLicense
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180' DAY
),
recent_edits AS (
  SELECT
    ph.PostId,
    ph.Id AS RevisionId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.UserId,
    ph.UserDisplayName,
    ph.Comment,
    ph.Text
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4,5,6,10,11,14,15,16,24,36)
),
top_tags AS (
  SELECT
    -- split tags like '<tag1><tag2>' into rows; use generic string functions
    TRIM(tag) AS TagName,
    p.Id AS PostId
  FROM Posts p,
  LATERAL (
    SELECT regexp_split_to_table(
      SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2)),
      '><'
    ) AS tag
  ) split
  WHERE p.PostTypeId = 1
),
tag_summary AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews
  FROM top_tags t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY t.TagName
  HAVING COUNT(*) >= 5
),
activity AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.LastActivityDate,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    MAX(v.CreationDate) AS LastVoteDate
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.Id, p.OwnerUserId, p.LastActivityDate
),
user_stats AS (
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
    u.AboutMe,
    u.ProfileImageUrl,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
    (SELECT COUNT(*) FROM Posts ps WHERE ps.OwnerUserId = u.Id AND ps.PostTypeId = 1) AS QuestionCount
  FROM Users u
),
complex_result AS (
  SELECT
    np.PostId,
    np.Title,
    np.Tags,
    np.CreationDate,
    np.LastActivityDate,
    np.Score,
    np.ViewCount,
    a.UpVotes,
    a.DownVotes,
    a.LastVoteDate,
    s.PostCount,
    s.AvgScore,
    s.TotalViews,
    u.UserId,
    u.DisplayName AS OwnerName,
    u.Reputation,
    u.CreationDate AS OwnerCreation,
    u.Location,
    u.BadgeCount,
    u.QuestionCount,
    array_agg(DISTINCT t.TagName) AS AllTagsOfPost
  FROM notable_posts np
  LEFT JOIN activity a ON a.PostId = np.PostId
  LEFT JOIN LATERAL (
    -- derive tag names for the current post to join against tag_summary
    SELECT regexp_split_to_table(
      SUBSTRING(np.Tags FROM 2 FOR (CHAR_LENGTH(np.Tags) - 2)),
      '><'
    ) AS TagName
  ) post_tags ON TRUE
  LEFT JOIN tag_summary s ON s.TagName = post_tags.TagName
  LEFT JOIN user_stats u ON u.UserId = np.OwnerUserId
  LEFT JOIN top_tags t ON t.PostId = np.PostId
  GROUP BY
    np.PostId, np.Title, np.Tags, np.CreationDate, np.LastActivityDate,
    np.Score, np.ViewCount, a.UpVotes, a.DownVotes, a.LastVoteDate,
    s.PostCount, s.AvgScore, s.TotalViews,
    u.UserId, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.BadgeCount, u.QuestionCount
)
SELECT
  cr.PostId,
  cr.Title,
  cr.Tags,
  cr.OwnerName,
  cr.Reputation,
  cr.OwnerCreation,
  cr.Location,
  cr.LastActivityDate,
  cr.Score,
  cr.ViewCount,
  cr.UpVotes,
  cr.DownVotes,
  cr.LastVoteDate,
  cr.AllTagsOfPost,
  cr.PostCount AS RelatedTagPostCount,
  cr.TotalViews AS RelatedTagTotalViews,
  cr.AvgScore AS RelatedTagAvgScore,
  cr.BadgeCount,
  cr.QuestionCount
FROM complex_result cr
WHERE cr.TotalViews > 1000
  AND cr.AvgScore > 0
ORDER BY cr.LastActivityDate DESC
LIMIT 100;