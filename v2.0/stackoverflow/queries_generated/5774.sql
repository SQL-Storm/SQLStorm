-- {"query": "5774.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1044} 
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
  WHERE p.CreationDate >= DATEADD(DAY, -30, CURRENT_TIMESTAMP)
),
TagSummary AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagPostCount,
    SUM(p.ViewCount) AS TotalViews,
    AVG(CASE WHEN p.Score IS NULL THEN 0 ELSE p.Score END) AS AvgPostScore,
    MAX(p.LastActivityDate) AS LastActive
  FROM RecentActivePosts p
  CROSS APPLY (SELECT value AS TagName FROM string_split(p.Tags, '><') ) AS s
  GROUP BY t.TagName
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
  ORDER BY TagPostCount DESC, TotalViews DESC
  FETCH FIRST 100 ROWS ONLY
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
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
    up.UpVotes,
    up.DownVotes,
    vu.UserName AS AuthorName,
    ca.CommentCountForPost,
    ca.PositiveComments,
    pv.UpVotes AS PostUpVotes,
    pv.DownVotes AS PostDownVotes,
    (pv.NetUpDown) AS NetVotes
  FROM RecentActivePosts r
  LEFT JOIN (
    SELECT t.TagName, t.TagPostCount
    FROM TopTags t
    WHERE t.rn = 1
  ) tc ON 1=1
  LEFT JOIN UserActivity vu ON vu.UserId = r.OwnerUserId
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