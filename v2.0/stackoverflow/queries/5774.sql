WITH 
RecentActivePosts AS (
  SELECT 
    p.Id,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.Body,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense
  FROM Posts p
  WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 day')
),
-- Split tags by treating the Tags string like '<tag1><tag2>' and extracting tag substrings
ExplodedTags AS (
  SELECT
    p.Id AS PostId,
    TRIM(BOTH '<>' FROM value) AS TagName
  FROM RecentActivePosts p,
  LATERAL (
    SELECT regexp_split_to_table(p.Tags, '><') AS value
  ) AS s
),
TagSummary AS (
  SELECT
    et.TagName,
    COUNT(*) AS TagPostCount,
    SUM(p.ViewCount) AS TotalViews,
    AVG(COALESCE(p.Score, 0)) AS AvgPostScore,
    MAX(p.LastActivityDate) AS LastActive
  FROM ExplodedTags et
  JOIN RecentActivePosts p ON p.Id = et.PostId
  GROUP BY et.TagName
),
TopTags AS (
  SELECT
    TagName,
    TagPostCount,
    TotalViews,
    AvgPostScore,
    LastActive,
    ROW_NUMBER() OVER (ORDER BY TagPostCount DESC, TotalViews DESC) AS rn
  FROM TagSummary
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
    SUM(p.ViewCount) AS TotalViewsByUser,
    MAX(p.LastActivityDate) AS LastActiveByUser
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
CommentInfluence AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCountForPost,
    SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveComments
  FROM Comments c
  GROUP BY c.PostId
),
PostVoteHealth AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    (SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)) AS NetUpDown
  FROM Votes v
  GROUP BY v.PostId
),
Combined AS (
  SELECT
    r.Id AS PostId,
    r.Title,
    r.PostTypeId,
    r.OwnerUserId,
    r.CreationDate,
    r.LastActivityDate,
    r.Tags,
    r.ViewCount,
    r.Score,
    tc.TagName AS TopTag,
    up.UserId AS UpvoterUserId,
    up.UpVotes AS UserUpVotes,
    up.DownVotes AS UserDownVotes,
    vu.UserName AS AuthorName,
    ua.TotalViewsByUser,
    ua.LastActiveByUser,
    ca.CommentCountForPost,
    ca.PositiveComments,
    pv.UpVotes AS PostUpVotes,
    pv.DownVotes AS PostDownVotes,
    pv.NetUpDown AS NetVotes
  FROM RecentActivePosts r
  LEFT JOIN (
    SELECT t.TagName, t.TagPostCount
    FROM TopTags t
    WHERE t.rn = 1
  ) tc ON 1=1
  LEFT JOIN UserActivity vu ON vu.UserId = r.OwnerUserId
  LEFT JOIN UserActivity ua ON ua.UserId = r.OwnerUserId
  LEFT JOIN CommentInfluence ca ON ca.PostId = r.Id
  LEFT JOIN PostVoteHealth pv ON pv.PostId = r.Id
  LEFT JOIN (
    SELECT UserId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY UserId
  ) up ON up.UserId = r.OwnerUserId
  WHERE (r.Tags LIKE '%<c1%>%' OR r.Tags IS NOT NULL)
)
SELECT
  c.PostId,
  c.Title,
  c.PostTypeId,
  c.OwnerUserId,
  c.CreationDate,
  c.LastActivityDate,
  c.TopTag,
  c.ViewCount,
  c.Score,
  c.AuthorName,
  c.TotalViewsByUser,
  c.LastActiveByUser,
  c.CommentCountForPost,
  c.PositiveComments,
  c.NetVotes
FROM Combined c
ORDER BY c.LastActivityDate DESC, c.Score DESC
LIMIT 100;