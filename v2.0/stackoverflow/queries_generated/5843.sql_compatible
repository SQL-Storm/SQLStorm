WITH
TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
),
UserActivity AS (
  SELECT
    u.UserId,
    u.DisplayName,
    COUNT(p.Id) AS PostCount,
    SUM(COALESCE(p.Score, 0)) AS ScoreSum,
    MAX(p.LastActivityDate) AS LastActivity,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    AVG(COALESCE(p.ViewCount, 0)) AS AvgViewCount,
    STRING_AGG(DISTINCT CASE WHEN p.Title IS NOT NULL THEN p.Title ELSE '' END, ',') AS TitleTags
  FROM TopUsers u
  LEFT JOIN Posts p ON p.OwnerUserId = u.UserId
  GROUP BY u.UserId, u.DisplayName
),
SelectedUsers AS (
  SELECT
    ua.UserId,
    ua.DisplayName,
    ua.PostCount,
    ua.ScoreSum,
    ua.LastActivity,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.AvgViewCount,
    ua.TitleTags
  FROM UserActivity ua
  ORDER BY ua.ScoreSum DESC NULLS LAST, ua.LastActivity DESC
  LIMIT 50
),
UserBadges AS (
  SELECT
    b.UserId,
    b.Name AS BadgeName,
    b.Date
  FROM Badges b
  WHERE b.Class IN (1,2,3)
),
PostEngagement AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.AcceptedAnswerId,
    p.ParentId,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesForPost,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesForPost
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.Id, p.OwnerUserId, p.PostTypeId, p.Title, p.Tags, p.CreationDate, p.LastActivityDate, p.ViewCount, p.Score, p.AcceptedAnswerId, p.ParentId
),
TagRadar AS (
  SELECT
    t.TagName,
    t.Count,
    t.IsModeratorOnly,
    t.IsRequired,
    ARRAY_AGG(DISTINCT pv.Id) FILTER (WHERE pv.Id IS NOT NULL) AS PostsUsingTag
  FROM Tags t
  LEFT JOIN Posts pv ON pv.Tags LIKE '%' || t.TagName || '%'
  GROUP BY t.TagName, t.Count, t.IsModeratorOnly, t.IsRequired
)
SELECT
  s.UserId,
  s.DisplayName,
  s.PostCount,
  s.ScoreSum,
  s.LastActivity,
  s.QuestionCount,
  s.AnswerCount,
  s.AvgViewCount,
  s.TitleTags,
  po.Id AS RecentPostId,
  po.Title AS RecentPostTitle,
  po.PostTypeId AS RecentPostType,
  po.LastActivityDate AS RecentPostActivity,
  (SELECT COUNT(*) FROM TagRadar tr WHERE tr.TagName <> '' AND po.Title LIKE '%' || tr.TagName || '%') AS TagMatchCount,
  (COALESCE(s.PostCount,0) * 0.5 + COALESCE(s.ScoreSum,0) * 1.5 + COALESCE(s.AvgViewCount,0) * 0.2) AS CompositeMetric,
  COALESCE(s.TitleTags, 'No Titles') AS TitleTagSnapshot
FROM SelectedUsers s
LEFT JOIN LATERAL (
  SELECT p.Id, p.Title, p.PostTypeId, p.LastActivityDate, p.OwnerUserId
  FROM Posts p
  WHERE p.OwnerUserId = s.UserId
  ORDER BY p.LastActivityDate DESC NULLS LAST
  LIMIT 1
) po ON true
ORDER BY CompositeMetric DESC NULLS LAST, s.LastActivity DESC
LIMIT 100;