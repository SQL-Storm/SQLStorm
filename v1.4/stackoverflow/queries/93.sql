-- {"query": "93.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 821} 
WITH
RecentActivePosts AS (
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
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastEditorUserId,
    p.LastEditorDisplayName
  FROM Posts p
  WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '60 days'
),
TagCte AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQuestionCount,
    AVG(p.Score) AS AvgScorePerQuestion,
    SUM(p.ViewCount) AS TotalViewsForTag
  FROM Tags t
  JOIN Posts p ON p.Id = t.ExcerptPostId
  WHERE p.PostTypeId = 1 -- questions
  GROUP BY t.TagName
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT rp.Id) AS PostsOpenedOrEdited,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
    MAX(p.LastActivityDate) AS LastActivePostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Posts rp ON rp.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
ComplexJoins AS (
  SELECT
    r.Id AS PostId,
    r.PostTypeId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.LastActivityDate,
    r.Score,
    r.ViewCount,
    r.CommentCount,
    r.AnswerCount,
    lh.Name AS HistoryTypeName,
    ph.CreationDate AS HistoryDate,
    ph.UserDisplayName AS EditorName,
    ph.Comment AS HistoryComment,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName
  FROM RecentActivePosts r
  LEFT JOIN PostHistory ph ON ph.PostId = r.Id AND ph.PostHistoryTypeId = 10 -- Post Closed
  LEFT JOIN PostHistoryTypes lh ON ph.PostHistoryTypeId = lh.Id
  LEFT JOIN PostLinks pl ON pl.PostId = r.Id
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE r.LastActivityDate > r.CreationDate - interval '0 days'
),
Summary AS (
  SELECT
    c.TagName,
    c.TagQuestionCount,
    c.AvgScorePerQuestion,
    c.TotalViewsForTag,
    ROW_NUMBER() OVER (ORDER BY c.TotalViewsForTag DESC, c.TagQuestionCount DESC) AS rn
  FROM TagCte c
)
SELECT
  s.rn,
  s.TagName,
  s.TagQuestionCount,
  s.AvgScorePerQuestion,
  s.TotalViewsForTag,
  cu.DisplayName AS TopContributor,
  au.UpvotesGiven,
  au.DownvotesGiven,
  au.LastActivePostDate
FROM Summary s
LEFT JOIN (
  SELECT
    ua.UserId,
    ua.DisplayName,
    MAX(ua.LastActivePostDate) AS MaxLastActive
  FROM UserActivity ua
  GROUP BY ua.UserId, ua.DisplayName
  ORDER BY MaxLastActive DESC
  LIMIT 1
) AS cu ON TRUE
LEFT JOIN UserActivity au ON au.UserId = (SELECT UserId FROM UserActivity ORDER BY LastActivePostDate DESC LIMIT 1)
WHERE s.rn <= 20
ORDER BY s.TotalViewsForTag DESC, s.AvgScorePerQuestion DESC;