WITH
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS PostCount,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
      AVG(p.Score) AS AveragePostScore,
      SUM(p.ViewCount) AS TotalViewCount,
      MAX(p.LastActivityDate) AS LastActivityDate,
      COUNT(DISTINCT c.Id) AS CommentCount,
      SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
      SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
      SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount,
      COUNT(DISTINCT pl.Id) AS PostLinkCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE 0 END) AS BountyStartCount,
      AVG(
        CAST(
          EXTRACT(EPOCH FROM (p.CreationDate - u.CreationDate)) / 86400.0
          AS NUMERIC
        )
      ) AS AvgDaysToFirstPost
    FROM
      Users u
      LEFT JOIN Posts p ON u.Id = p.OwnerUserId
      LEFT JOIN Comments c ON u.Id = c.UserId AND p.Id = c.PostId
      LEFT JOIN Badges b ON u.Id = b.UserId
      LEFT JOIN PostLinks pl ON u.Id = pl.PostId
      LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.CreationDate
  ),
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      pt.Name AS PostType,
      p.Title,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      p.CommunityOwnedDate,
      COALESCE(p.Score, 0) + COALESCE(p.ViewCount, 0) AS EngagementScore,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRankByDate,
      SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS DuplicateLinkCount,
      COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountPerPost,
      (
        SELECT
          COUNT(*)
        FROM
          Votes v_inner
        WHERE
          v_inner.PostId = p.Id AND v_inner.VoteTypeId = 2
      ) AS UpVoteCountPerPost,
      (
        SELECT
          COUNT(*)
        FROM
          Votes v_inner
        WHERE
          v_inner.PostId = p.Id AND v_inner.VoteTypeId = 3
      ) AS DownVoteCountPerPost
    FROM
      Posts p
      JOIN PostTypes pt ON p.PostTypeId = pt.Id
      LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 3
      LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
  )
SELECT
  ua.DisplayName,
  ua.PostCount,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.AcceptedAnswerCount,
  ua.AveragePostScore,
  ua.TotalViewCount,
  ua.LastActivityDate,
  ua.CommentCount AS UserCommentCount,
  ua.GoldBadgeCount,
  ua.SilverBadgeCount,
  ua.BronzeBadgeCount,
  ua.PostLinkCount AS UserPostLinkCount,
  ua.UpVoteCount AS UserUpVoteCount,
  ua.DownVoteCount AS UserDownVoteCount,
  ua.BountyStartCount AS UserBountyStartCount,
  ua.AvgDaysToFirstPost,
  pe.Title AS LatestPostTitle,
  pe.PostRankByDate,
  pe.EngagementScore AS LatestPostEngagement,
  pe.DuplicateLinkCount AS LatestPostDuplicateLinks,
  pe.CommentCountPerPost AS LatestPostCommentCount,
  pe.UpVoteCountPerPost AS LatestPostUpVoteCount,
  pe.DownVoteCountPerPost AS LatestPostDownVoteCount,
  CASE
    WHEN pe.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN pe.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS LatestPostStatus,
  LOWER(SUBSTRING(ua.DisplayName FROM 1 FOR 3)) AS DisplayNamePrefix,
  CASE
    WHEN ua.LastActivityDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months') THEN 'Recent'
    WHEN ua.LastActivityDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year') THEN 'ActiveLastYear'
    ELSE 'Inactive'
  END AS ActivityLevel
FROM
  UserActivity ua
  LEFT JOIN PostEngagement pe ON ua.UserId = pe.OwnerUserId AND pe.PostRankByDate = 1
WHERE
  ua.PostCount > 10
  AND ua.AveragePostScore > 5
  AND ua.GoldBadgeCount >= 1
  AND ua.DisplayName ~ '[^a-zA-Z0-9 ]'
ORDER BY
  ua.TotalViewCount DESC,
  ua.AveragePostScore DESC;