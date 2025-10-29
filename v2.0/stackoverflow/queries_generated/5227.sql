-- {"query": "5227.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 808} 
WITH
-- 1) aggregate yearly activity per user with complex metrics
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    DATE_TRUNC('year', u.CreationDate) AS CreationYear,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(COALESCE(p.Score,0)) AS ScoreSum,
    SUM(COALESCE(p.ViewCount,0)) AS ViewsTotal,
    COUNT(DISTINCT c.Id) AS CommentCountTotal,
    COUNT(DISTINCT v.PostId) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesCast,
    COUNT(DISTINCT v.PostId) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesCast,
    MAX(p.LastActivityDate) AS LastActive
  FROM
    Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE
    u.Id IS NOT NULL
  GROUP BY
    u.Id, u.DisplayName, DATE_TRUNC('year', u.CreationDate)
),
-- 2) recent badges per user with tag-based and named badges
UserBadges AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount,
    STRING_AGG(CASE WHEN b.TagBased = 1 THEN CONCAT('Tag-', b.Name) ELSE b.Name END, ',') AS BadgesList
  FROM Badges b
  GROUP BY b.UserId
),
-- 3) recent post history cross-joined to fetch close reasons and actions
PostHistorySummary AS (
  SELECT
    ph.PostId,
    MAX(ph.CreationDate) AS LastHistoryDate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS CloseReasonComment,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN CAST(ph.Text AS varchar(1000)) END) AS CloseReasonIdRaw
  FROM PostHistory ph
  GROUP BY ph.PostId
),
-- 4) correlate posts with tag info and derived tag-length features
PostsTagStats AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    (LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '<', '')) )::int AS TagCountApprox,
    ARRAY_LENGTH(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'), 1) AS TagArraySize
  FROM Posts p
  WHERE p.PostTypeId = 1
)
SELECT
  ua.UserId,
  ua.UserName,
  ua.CreationYear,
  ua.QuestionCount,
  ua.TotalPosts,
  ua.ScoreSum,
  ua.ViewsTotal,
  ua.CommentCountTotal,
  ua.UpVotesCast,
  ua.DownVotesCast,
  ua.LastActive,
  COALESCE(ub.BadgeCount, 0) AS BadgeCount,
  COALESCE(ub.BadgesList, '') AS BadgesList,
  COALESCE(pst.TagCountApprox, 0) AS TagCountApprox,
  COALESCE(pst.TagArraySize, 0) AS TagArraySize
FROM UserActivity ua
LEFT JOIN UserBadges ub ON ub.UserId = ua.UserId
LEFT JOIN PostsTagStats pst ON pst.PostId = (
  SELECT p.Id FROM Posts p
  WHERE p.OwnerUserId = ua.UserId
  ORDER BY p.LastActivityDate DESC
  LIMIT 1
)
WHERE
  ua.TotalPosts > 0
ORDER BY
  ua.LastActive DESC
LIMIT 100;