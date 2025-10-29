-- {"query": "5253.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 864} 
WITH top_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.Views,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1
),
recent_edits AS (
  SELECT
    ph.PostId,
    ph.CreationDate AS EditDate,
    ph.UserId AS EditorUserId,
    ph.UserDisplayName AS EditorDisplayName,
    ph.Text
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4,5,6,16,36) -- edits to Title/Body/Tags or migrations
),
tag_summary AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    t.IsModeratorOnly,
    t.IsRequired,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
complex_flags AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpvotesFromVotes,
    SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownvotesFromVotes,
    MAX(CASE WHEN vte.Name IS NOT NULL THEN vte.Name END) AS LastVoteType
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  LEFT JOIN VoteTypes vte ON v.VoteTypeId = vte.Id
  GROUP BY v.PostId
),
linked AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName,
    pl.CreationDate,
    l.Name AS RelatedPostOwner
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  LEFT JOIN Posts l ON pl.RelatedPostId = l.Id
  WHERE lt.Name IN ('Linked', 'Duplicate')
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.LastActivityDate,
    p.LastEditorUserId,
    u.DisplayName AS LastEditorDisplayName
  FROM Posts p
  LEFT JOIN Users u ON p.LastEditorUserId = u.Id
),
aggregated AS (
  SELECT
    tq.PostId,
    tq.Title,
    tq.Tags,
    tq.CreationDate,
    tq.Score,
    tq.Views,
    tq.OwnerDisplayName,
    qa.EditDate,
    qa.EditorDisplayName,
    ca.LastActivityDate,
    ca.LastEditorDisplayName,
    tc.UpvotesFromVotes,
    tc.DownvotesFromVotes,
    ts.TagName
  FROM top_questions tq
  LEFT JOIN recent_edits qa ON qa.PostId = tq.PostId
  LEFT JOIN complex_flags tc ON tc.PostId = tq.PostId
  LEFT JOIN recent_activity ca ON ca.PostId = tq.PostId
  LEFT JOIN linked l ON l.PostId = tq.PostId
  LEFT JOIN tag_summary ts ON ts.TagName = ANY(string_to_array(substr(tq.Tags, 2, length(tq.Tags)-2), '><'))
)
SELECT
  a.PostId,
  a.Title,
  a.Tags,
  a.CreationDate,
  a.Score,
  a.Views,
  a.OwnerDisplayName AS Owner,
  a.EditDate,
  a.EditorDisplayName,
  a.LastActivityDate,
  a.LastEditorDisplayName,
  a.UpvotesFromVotes,
  a.DownvotesFromVotes,
  a.TagName AS MostProminentTag,
  CASE
    WHEN a.Views > 1000 THEN 'High'
    WHEN a.Views > 100 THEN 'Medium'
    ELSE 'Low'
  END AS ViewTier,
  CONCAT_WS(' | ', a.Title, a.Tags, a.OwnerDisplayName) AS TitleTagComposite
FROM aggregated a
ORDER BY a.LastActivityDate DESC NULLS LAST
LIMIT 100;