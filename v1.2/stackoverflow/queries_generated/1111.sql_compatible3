WITH RECURSIVE RecursiveAllParents AS (
  SELECT Id, ParentId, 1 AS Level
  FROM Posts
  WHERE ParentId IS NOT NULL
  UNION ALL
  SELECT p.Id, p.ParentId, rap.Level + 1
  FROM Posts p
  JOIN RecursiveAllParents rap ON p.ParentId = rap.Id
),
UserBadgesRanked AS (
  SELECT 
    b.UserId,
    b.Name AS BadgeName,
    b.Class,
    dense_rank() OVER (PARTITION BY b.UserId ORDER BY b.Class) AS BadgeClassRank
  FROM Badges b
),
UserActivity AS (
  SELECT 
    u.Id AS UserId,
    u.DisplayName,
    COALESCE(u.Reputation,0) AS Reputation,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersCount,
    COUNT(DISTINCT c.Id) AS CommentsCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCount,
    MAX(p.CreationDate) AS LastPostDate,
    MAX(c.CreationDate) AS LastCommentDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUserPosts AS (
  SELECT
    p.OwnerUserId,
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    row_number() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
),
QuestionsAnswersWithLinks AS (
  SELECT
    q.Id AS QuestionId,
    COALESCE(a.Id,-1) AS AnswerId,
    q.OwnerUserId AS QuestionOwner,
    a.OwnerUserId AS AnswerOwner,
    q.CreationDate AS QuestionCreation,
    a.CreationDate AS AnswerCreation,
    q.Score AS QuestionScore,
    a.Score AS AnswerScore,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName,
    q.Tags,
    array_to_string(string_to_array(substring(q.Tags FROM 2 FOR char_length(q.Tags)-2), '><'), ',') AS ParsedTags
  FROM Posts q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  LEFT JOIN PostLinks pl ON pl.PostId = q.Id AND pl.RelatedPostId = a.Id
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  WHERE q.PostTypeId = 1
),
CloseReasonsSummary AS (
  SELECT
    pht.PostId,
    crt.Name AS CloseReasonName,
    count(*) AS CloseVotesCount
  FROM PostHistory pht
  LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(pht.Comment AS smallint)
  WHERE pht.PostHistoryTypeId = 10 AND crt.Id IS NOT NULL
  GROUP BY pht.PostId, crt.Name
),
UserBadgeCounts AS (
  SELECT
    b.UserId,
    b.Class,
    count(*) AS BadgeCount
  FROM Badges b
  GROUP BY b.UserId, b.Class
),
RankedPostsByActivity AS (
  SELECT
    p.Id,
    p.OwnerUserId,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    count(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotes,
    row_number() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRankPerUser
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.Id, p.OwnerUserId, p.PostTypeId, p.Score, p.ViewCount, p.CreationDate
)
SELECT DISTINCT 
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.QuestionsCount,
  ua.AnswersCount,
  ua.CommentsCount,
  ua.UpVotesCount,
  ua.DownVotesCount,
  ubc.Class AS BadgeClass,
  ubc.BadgeCount,
  tup.PostId AS TopPostId,
  rp.ActivityScore,
  crs.CloseReasonName,
  qal.ParsedTags,
  extract(epoch FROM (CAST('2024-10-01 12:34:56' AS timestamp) - ua.LastPostDate))/86400 AS DaysSinceLastPost,
  CASE WHEN ua.UpVotesCount > ua.DownVotesCount THEN 'Positive' 
       WHEN ua.DownVotesCount > ua.UpVotesCount THEN 'Negative'
       ELSE 'Neutral' END AS VoteSentiment,
  rp.PostRankPerUser,
  rac.PostCountRanks
FROM UserActivity ua
LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = ua.UserId AND ubc.Class = 1
LEFT JOIN TopUserPosts tup ON tup.OwnerUserId = ua.UserId AND tup.rn = 1
LEFT JOIN (
  SELECT 
    p.Id,
    (p.Score * 2 + COALESCE(voteups.UpVotes,0) - COALESCE(votedowns.DownVotes,0) + COALESCE(cmt.Comments, 0)) AS ActivityScore,
    row_number() OVER (PARTITION BY p.OwnerUserId ORDER BY (p.Score * 2 + COALESCE(voteups.UpVotes,0) - COALESCE(votedowns.DownVotes,0) + COALESCE(cmt.Comments, 0)) DESC) AS PostRankPerUser
  FROM Posts p
  LEFT JOIN (
    SELECT PostId, count(*) AS UpVotes FROM Votes WHERE VoteTypeId = 2 GROUP BY PostId
  ) voteups ON voteups.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, count(*) AS DownVotes FROM Votes WHERE VoteTypeId = 3 GROUP BY PostId
  ) votedowns ON votedowns.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, count(*) AS Comments FROM Comments GROUP BY PostId
  ) cmt ON cmt.PostId = p.Id
) rp ON rp.Id = tup.PostId
LEFT JOIN CloseReasonsSummary crs ON crs.PostId = tup.PostId
LEFT JOIN QuestionsAnswersWithLinks qal ON qal.QuestionId = tup.PostId
LEFT JOIN (
  SELECT OwnerUserId, count(*) AS PostCountRanks 
  FROM RankedPostsByActivity
  GROUP BY OwnerUserId
) rac ON rac.OwnerUserId = ua.UserId
WHERE ua.Reputation > 1000
  AND (ua.UpVotesCount - ua.DownVotesCount) > 0
  AND (tup.PostId IS NOT NULL OR tup.PostId = -1)
ORDER BY ua.Reputation DESC, rp.ActivityScore DESC
LIMIT 100;