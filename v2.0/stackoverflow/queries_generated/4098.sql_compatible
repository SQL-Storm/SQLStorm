WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      pt.Name AS PostTypeName,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_creation,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS rn_score,
      AVG(CAST(p.Score AS DECIMAL(10, 2))) OVER (PARTITION BY p.PostTypeId) AS avg_score_for_type,
      SUM(p.ViewCount) OVER (ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total_views,
      LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS previous_post_score
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
  ),
  UserEngagement AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
      SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentsMade,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
      AVG(CAST(p.Score AS DECIMAL(10, 2))) AS AvgPostScore,
      MAX(p.CreationDate) AS LastPostDate
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c
      ON u.Id = c.UserId
    LEFT JOIN Votes AS v
      ON u.Id = v.UserId
    WHERE
      u.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '365 day')
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
    HAVING
      COUNT(DISTINCT p.Id) > 10
  ),
  AggregatedPostInfo AS (
    SELECT
      rp.PostId,
      rp.PostTypeName,
      rp.OwnerUserId,
      rp.Score,
      rp.ViewCount,
      rp.AnswerCount,
      rp.CommentCount,
      rp.FavoriteCount,
      rp.ClosedDate,
      ue.Reputation AS OwnerReputation,
      ue.TotalPosts AS OwnerTotalPosts,
      CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsClosed,
      CASE
        WHEN rp.Score > 100 AND rp.FavoriteCount > 10 THEN 'Popular & Highly Rated'
        WHEN rp.Score < 0 THEN 'Poorly Rated'
        WHEN rp.AnswerCount > 5 AND rp.CommentCount > 10 THEN 'Highly Discussed'
        ELSE 'Standard'
      END AS PostStatusCategory,
      rp.rn_score,
      rp.avg_score_for_type,
      rp.running_total_views,
      rp.previous_post_score,
      rp.PostTypeName || '-' || CAST(rp.Score AS VARCHAR) AS TypeAndScore,
      rp.PostTypeId
    FROM RankedPosts AS rp
    LEFT JOIN UserEngagement AS ue
      ON rp.OwnerUserId = ue.UserId
    WHERE
      rp.PostTypeId IN (1, 2) AND rp.Score >= 0
  )
SELECT
  api.PostId,
  api.PostTypeName,
  api.OwnerUserId,
  api.OwnerReputation,
  api.OwnerTotalPosts,
  api.Score,
  api.ViewCount,
  api.AnswerCount,
  api.CommentCount,
  api.FavoriteCount,
  api.ClosedDate,
  api.IsClosed,
  api.PostStatusCategory,
  api.rn_score,
  api.avg_score_for_type,
  api.running_total_views,
  api.previous_post_score,
  api.TypeAndScore,
  (
    SELECT
      COUNT(*)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = api.PostId AND pl.LinkTypeId = 3
  ) AS DuplicateLinkCount,
  CASE
    WHEN api.PostTypeName = 'Question' AND api.Score > 50 THEN 'High-Value Question'
    WHEN api.PostTypeName = 'Answer' AND api.Score > 20 THEN 'High-Value Answer'
    ELSE 'Standard Post'
  END AS ValueCategory
FROM AggregatedPostInfo AS api
WHERE
  api.Score > (api.avg_score_for_type * 0.5)
  OR api.ViewCount > 1000
ORDER BY
  api.OwnerReputation DESC,
  api.Score DESC
LIMIT 100;