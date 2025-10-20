WITH UserActivity AS (
  SELECT 
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
    COUNT(DISTINCT b.Id) AS BadgesEarned,
    COALESCE(SUM(vtUp.VoteCount), 0) AS TotalUpVotes,
    COALESCE(SUM(vtDown.VoteCount), 0) AS TotalDownVotes,
    MAX(p.LastActivityDate) AS LastPostActivity,
    AVG(p.Score) AS AvgPostScore
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS VoteCount 
    FROM Votes 
    WHERE VoteTypeId = 2
    GROUP BY PostId
  ) vtUp ON vtUp.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS VoteCount
    FROM Votes
    WHERE VoteTypeId = 3
    GROUP BY PostId
  ) vtDown ON vtDown.PostId = p.Id
  GROUP BY u.Id, u.DisplayName
),
TopUsers AS (
  SELECT UserId, DisplayName, TotalPosts, QuestionsAsked, AnswersGiven, BadgesEarned, TotalUpVotes, TotalDownVotes, LastPostActivity, AvgPostScore
  FROM UserActivity
  WHERE TotalPosts > 50 AND TotalUpVotes > TotalDownVotes
  ORDER BY TotalUpVotes DESC
  LIMIT 20
),
UserPostsWithComments AS (
  SELECT 
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Score,
    p.CreationDate,
    p.OwnerUserId,
    COUNT(c.Id) AS CommentCount,
    SUM(COALESCE(cv.Score,0)) AS TotalCommentScore
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Comments cv ON cv.PostId = p.Id
  WHERE p.OwnerUserId IN (SELECT UserId FROM TopUsers)
  GROUP BY p.Id, p.PostTypeId, p.Title, p.Score, p.CreationDate, p.OwnerUserId
),
PostTagAggregates AS (
  SELECT
    up.PostId,
    STRING_AGG(t.TagName, ', ') AS Tags,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS UserAvgScore,
    p.OwnerUserId
  FROM UserPostsWithComments up
  JOIN Posts p ON p.Id = up.PostId
  LEFT JOIN (
    SELECT id, unnest(string_to_array(substring(tags, 2, length(tags) -2), '><')) AS TagName
    FROM Posts
  ) t ON t.id = p.Id
  GROUP BY up.PostId, p.OwnerUserId, p.Score
),
PostLinkCounts AS (
  SELECT 
    pl.PostId,
    COUNT(DISTINCT CASE WHEN lt.Name = 'Linked' THEN pl.RelatedPostId END) AS LinkedCount,
    COUNT(DISTINCT CASE WHEN lt.Name = 'Duplicate' THEN pl.RelatedPostId END) AS DuplicateCount
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE pl.PostId IN (SELECT PostId FROM UserPostsWithComments)
  GROUP BY pl.PostId
),
RecentUserEdits AS (
  SELECT 
    ph.UserId,
    COUNT(*) AS EditCount,
    MAX(ph.CreationDate) AS LastEditDate
  FROM PostHistory ph
  WHERE ph.UserId IN (SELECT UserId FROM TopUsers)
  GROUP BY ph.UserId
)
SELECT 
  tu.UserId,
  tu.DisplayName,
  tu.TotalPosts,
  tu.QuestionsAsked,
  tu.AnswersGiven,
  tu.BadgesEarned,
  tu.TotalUpVotes,
  tu.TotalDownVotes,
  tu.LastPostActivity,
  tu.AvgPostScore,
  upc.PostId,
  upc.PostTypeId,
  upc.Title,
  upc.Score AS PostScore,
  upc.CommentCount,
  upc.TotalCommentScore,
  pta.Tags,
  plc.LinkedCount,
  plc.DuplicateCount,
  rue.EditCount,
  rue.LastEditDate
FROM TopUsers tu
LEFT JOIN UserPostsWithComments upc ON upc.OwnerUserId = tu.UserId
LEFT JOIN PostTagAggregates pta ON pta.PostId = upc.PostId
LEFT JOIN PostLinkCounts plc ON plc.PostId = upc.PostId
LEFT JOIN RecentUserEdits rue ON rue.UserId = tu.UserId
ORDER BY tu.TotalUpVotes DESC, upc.Score DESC NULLS LAST, upc.CommentCount DESC NULLS LAST
LIMIT 100;