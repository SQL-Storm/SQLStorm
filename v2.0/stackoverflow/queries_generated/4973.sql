-- {"query": "4973.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1152} 
WITH
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      COALESCE(
        (
          SELECT
            COUNT(*)
          FROM
            Comments c
          WHERE
            c.PostId = p.Id
        ),
        0
      ) AS TotalComments,
      COALESCE(
        (
          SELECT
            COUNT(*)
          FROM
            Votes v
          WHERE
            v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
        ),
        0
      ) AS TotalVotes,
      COALESCE(
        (
          SELECT
            COUNT(*)
          FROM
            PostLinks pl
          WHERE
            pl.PostId = p.Id AND pl.LinkTypeId = 3
        ),
        0
      ) AS DuplicateLinks
    FROM
      Posts p
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.Reputation,
      u.CreationDate,
      u.DisplayName,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      (
        SELECT
          COUNT(*)
        FROM
          Badges b
        WHERE
          b.UserId = u.Id
      ) AS TotalBadges,
      (
        SELECT
          COUNT(*)
        FROM
          PostHistory ph
        WHERE
          ph.UserId = u.Id AND ph.PostHistoryTypeId IN (2, 5)
        GROUP BY
          ph.UserId
      ) AS PostEdits,
      COALESCE(
        (
          SELECT
            AVG(pe.Score)
          FROM
            PostEngagement pe
          WHERE
            pe.OwnerUserId = u.Id AND pe.PostTypeId = 1
        ),
        0
      ) AS AvgQuestionScore,
      COALESCE(
        (
          SELECT
            SUM(pe.ViewCount)
          FROM
            PostEngagement pe
          WHERE
            pe.OwnerUserId = u.Id AND pe.PostTypeId = 1
        ),
        0
      ) AS TotalQuestionViews
    FROM
      Users u
  )
SELECT
  ua.DisplayName,
  ua.Reputation,
  ua.TotalBadges,
  ua.PostEdits,
  ua.AvgQuestionScore,
  ua.TotalQuestionViews,
  SUM(pe.Score) AS TotalPostScore,
  SUM(pe.ViewCount) AS TotalPostViews,
  SUM(pe.TotalComments) AS TotalPostComments,
  SUM(pe.TotalVotes) AS TotalPostVotes,
  SUM(pe.DuplicateLinks) AS TotalDuplicateLinks,
  COUNT(pe.PostId) AS NumberOfPosts,
  CASE
    WHEN SUM(pe.Score) > 1000 THEN 'High Score'
    WHEN SUM(pe.ViewCount) > 10000 THEN 'High Views'
    WHEN SUM(pe.TotalComments) > 50 THEN 'High Comments'
    ELSE 'Moderate Activity'
  END AS ActivityLevel,
  'UserPerformance' AS ReportType
FROM
  UserActivity ua
LEFT OUTER JOIN
  PostEngagement pe ON ua.UserId = pe.OwnerUserId
WHERE
  ua.Reputation > 500
GROUP BY
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.TotalBadges,
  ua.PostEdits,
  ua.AvgQuestionScore,
  ua.TotalQuestionViews
HAVING
  COUNT(pe.PostId) > 5
UNION ALL
SELECT
  'Community User' AS DisplayName,
  AVG(u.Reputation) AS Reputation,
  COUNT(DISTINCT b.Id) AS TotalBadges,
  COUNT(DISTINCT ph.Id) AS PostEdits,
  AVG(pe.Score) AS AvgQuestionScore,
  SUM(pe.ViewCount) AS TotalQuestionViews,
  SUM(pe.Score) AS TotalPostScore,
  SUM(pe.ViewCount) AS TotalPostViews,
  SUM(pe.TotalComments) AS TotalPostComments,
  SUM(pe.TotalVotes) AS TotalPostVotes,
  SUM(pe.DuplicateLinks) AS TotalDuplicateLinks,
  COUNT(pe.PostId) AS NumberOfPosts,
  'Community Performance' AS ActivityLevel,
  'CommunityPerformance' AS ReportType
FROM
  PostEngagement pe
JOIN
  Users u ON pe.OwnerUserId = u.Id
LEFT OUTER JOIN
  Badges b ON u.Id = b.UserId
LEFT OUTER JOIN
  PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (2, 5)
WHERE
  pe.OwnerUserId = -1 -- Community User ID is often -1
GROUP BY
  pe.OwnerUserId
ORDER BY
  Reputation DESC;