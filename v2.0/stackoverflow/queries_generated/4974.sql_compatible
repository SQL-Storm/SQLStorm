WITH
  QuestionAnswers AS (
    SELECT
      q.Id AS QuestionId,
      q.Title AS QuestionTitle,
      q.OwnerUserId AS QuestionOwnerUserId,
      q.CreationDate AS QuestionCreationDate,
      COUNT(a.Id) AS AnswerCount,
      SUM(a.Score) AS TotalAnswerScore,
      AVG(a.Score) AS AverageAnswerScore,
      MAX(a.CreationDate) AS LastAnswerDate,
      RANK() OVER (ORDER BY COUNT(a.Id) DESC) AS RankByAnswerCount
    FROM
      Posts q
      JOIN Posts a
        ON q.Id = a.ParentId
    WHERE
      q.PostTypeId = 1
      AND a.PostTypeId = 2
      AND q.ClosedDate IS NULL
      AND a.ClosedDate IS NULL
    GROUP BY
      q.Id,
      q.Title,
      q.OwnerUserId,
      q.CreationDate
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT ph.PostId) AS PostHistoryCount,
      SUM(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 ELSE 0 END) AS BodyEditCount,
      SUM(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS TitleEditCount,
      SUM(CASE WHEN ph.PostHistoryTypeId = 6 THEN 1 ELSE 0 END) AS TagEditCount,
      AVG(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS AvgUpvoteRatio,
      COUNT(DISTINCT v.Id) AS TotalVotes
    FROM
      Users u
      LEFT JOIN PostHistory ph
        ON u.Id = ph.UserId
      LEFT JOIN Votes v
        ON u.Id = v.UserId
    WHERE
      u.Views > 1000
      AND u.UpVotes > u.DownVotes * 2
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  ),
  PostMetrics AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.Score,
      p.ViewCount,
      p.CommentCount,
      p.FavoriteCount,
      p.CreationDate,
      p.LastActivityDate,
      pt.Name AS PostTypeName,
      CASE
        WHEN p.PostTypeId = 1 THEN COALESCE(qa.AnswerCount, 0)
        ELSE 0
      END AS AnswerCount,
      COALESCE(p.OwnerUserId, -1) AS PostOwnerUserId,
      LOWER(REPLACE(REPLACE(REPLACE(p.Title, '?', ''), '.', ''), ' ', '_')) AS NormalizedTitle
    FROM
      Posts p
      JOIN PostTypes pt
        ON p.PostTypeId = pt.Id
      LEFT JOIN QuestionAnswers qa
        ON p.Id = qa.QuestionId
    WHERE
      p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year')
      AND p.Score > 0
      AND p.ViewCount > 50
  )
SELECT
  pm.PostId,
  pm.Title AS PostTitle,
  pm.PostTypeName,
  pm.Score,
  pm.ViewCount,
  pm.AnswerCount,
  pm.FavoriteCount,
  pm.CreationDate AS PostCreationDate,
  pm.LastActivityDate,
  ua.DisplayName AS UserDisplayName,
  ua.Reputation AS UserReputation,
  ua.UserCreationDate,
  ua.PostHistoryCount,
  ua.BodyEditCount,
  ua.TitleEditCount,
  ua.TagEditCount,
  ua.AvgUpvoteRatio,
  qa.RankByAnswerCount,
  CASE
    WHEN pm.NormalizedTitle LIKE '%sql%' THEN 'SQL Related'
    WHEN pm.NormalizedTitle LIKE '%python%' THEN 'Python Related'
    WHEN pm.NormalizedTitle LIKE '%java%' THEN 'Java Related'
    ELSE 'Other'
  END AS LanguageCategory,
  CASE
    WHEN (pm.ViewCount * 1.0 / NULLIF(pm.AnswerCount, 0)) > 100
      AND pm.AnswerCount > 5 THEN 'High View-to-Answer Ratio'
    WHEN pm.FavoriteCount > 50 THEN 'Highly Favorited'
    ELSE 'Standard Engagement'
  END AS EngagementLevel,
  (
    SELECT
      MAX(c.CreationDate)
    FROM
      Comments c
    WHERE
      c.PostId = pm.PostId
  ) AS LatestCommentDate
FROM
  PostMetrics pm
  LEFT JOIN UserActivity ua
    ON pm.PostOwnerUserId = ua.UserId
  LEFT JOIN QuestionAnswers qa
    ON pm.PostId = qa.QuestionId
WHERE
  (ua.TotalVotes > 1000 OR ua.Reputation > 50000)
ORDER BY
  pm.Score DESC,
  pm.ViewCount DESC
LIMIT 100;