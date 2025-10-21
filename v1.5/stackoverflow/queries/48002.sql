WITH UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
    COUNT(DISTINCT b.Id) AS BadgeCount
  FROM Users u
  LEFT JOIN Comments c
    ON u.Id = c.UserId
  LEFT JOIN Posts p
    ON u.Id = p.OwnerUserId
  LEFT JOIN Votes v
    ON u.Id = v.UserId
  LEFT JOIN Badges b
    ON u.Id = b.UserId
  WHERE
    u.Reputation > 10000
  GROUP BY
    u.Id,
    u.DisplayName
), PostEngagement AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    COUNT(DISTINCT c.Id) AS CommentCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
    COUNT(DISTINCT pl.Id) AS LinkCount
  FROM Posts p
  LEFT JOIN Comments c
    ON p.Id = c.PostId
  LEFT JOIN Votes v
    ON p.Id = v.PostId
  LEFT JOIN PostLinks pl
    ON p.Id = pl.PostId
  WHERE
    p.PostTypeId = 1 AND p.CreationDate >= DATE 'now' - INTERVAL '365' DAY
  GROUP BY
    p.Id,
    p.Title
)
SELECT
  ua.DisplayName,
  ua.PostCount,
  ua.CommentCount,
  ua.UpVoteCount AS UserUpVotes,
  ua.DownVoteCount AS UserDownVotes,
  ua.BadgeCount,
  pe.Title AS MostEngagedPostTitle,
  pe.CommentCount AS PostCommentCount,
  pe.UpVoteCount AS PostUpVotes,
  pe.DownVoteCount AS PostDownVotes,
  pe.LinkCount AS PostLinkCount
FROM UserActivity ua
JOIN PostEngagement pe
  ON ua.UserId = (
    SELECT
      OwnerUserId
    FROM Posts
    WHERE
      PostTypeId = 1
    ORDER BY
      Score DESC
    LIMIT 1
  )
ORDER BY
  ua.DisplayName DESC
LIMIT 10;