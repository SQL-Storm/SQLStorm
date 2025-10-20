-- {"query": "48002.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 619} 

WITH UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
    COUNT(DISTINCT b.Id) AS BadgeCount
  FROM Users AS u
  LEFT JOIN Comments AS c
    ON u.Id = c.UserId
  LEFT JOIN Posts AS p
    ON u.Id = p.OwnerUserId
  LEFT JOIN Votes AS v
    ON u.Id = v.UserId
  LEFT JOIN Badges AS b
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
  FROM Posts AS p
  LEFT JOIN Comments AS c
    ON p.Id = c.PostId
  LEFT JOIN Votes AS v
    ON p.Id = v.PostId
  LEFT JOIN PostLinks AS pl
    ON p.Id = pl.PostId
  WHERE
    p.PostTypeId = 1 AND p.CreationDate >= DATE('now', '-365 day')
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
FROM UserActivity AS ua
JOIN PostEngagement AS pe
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
  ua.Reputation DESC
LIMIT 10;
