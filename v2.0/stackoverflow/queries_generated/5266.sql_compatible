WITH
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    COUNT(p.Id) AS PostCount,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.LastActivityDate) AS LastActivity,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    u.Location, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
TopInteraction AS (
  SELECT
    ua.UserId,
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.Score,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountForPost,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpvoteCountForPost,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownvoteCountForPost,
    ROW_NUMBER() OVER (PARTITION BY ua.UserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM UserActivity ua
  JOIN Posts p ON p.OwnerUserId = ua.UserId
  WHERE p.LastActivityDate IS NOT NULL
),
EngagedUsers AS (
  SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.UserCreationDate,
    ua.LastAccessDate,
    ua.Location,
    ua.Views,
    ua.UpVotes,
    ua.DownVotes,
    ua.AccountId,
    ua.PostCount,
    ua.AvgPostScore,
    ua.LastActivity,
    ua.BadgeCount,
    (SELECT SUM(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = ua.UserId) AS TotalScoreFromPosts,
    (SELECT SUM(t.CommentCountForPost) FROM TopInteraction t WHERE t.UserId = ua.UserId) AS TotalComments
  FROM UserActivity ua
),
Final AS (
  SELECT
    eu.UserId,
    eu.DisplayName,
    eu.Reputation,
    eu.PostCount,
    eu.AvgPostScore,
    eu.LastActivity,
    eu.BadgeCount,
    ti.PostId,
    ti.Title,
    ti.Score AS PostScore,
    ti.CommentCountForPost,
    pl.RelatedPostId,
    p2.Title AS RelatedPostTitle,
    v2.VoteCount AS OpenVotesForUser
  FROM EngagedUsers eu
  LEFT JOIN TopInteraction ti
    ON ti.UserId = eu.UserId AND ti.rn = 1
  LEFT JOIN PostLinks pl ON pl.PostId = ti.PostId
  LEFT JOIN Posts p2 ON p2.Id = pl.RelatedPostId
  LEFT JOIN (
    SELECT
      p.OwnerUserId,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS VoteCount
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.OwnerUserId
  ) v2 ON v2.OwnerUserId = eu.UserId
  WHERE eu.TotalScoreFromPosts IS NOT NULL
)
SELECT
  *
FROM Final
ORDER BY Reputation DESC, PostCount DESC, LastActivity DESC
LIMIT 100;