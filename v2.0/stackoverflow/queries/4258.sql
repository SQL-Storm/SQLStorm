WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.Title,
      p.Score,
      p.FavoriteCount,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.ClosedDate,
      ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.FavoriteCount DESC, p.ViewCount DESC) AS ScoreRank,
      ROW_NUMBER() OVER (ORDER BY p.FavoriteCount DESC, p.Score DESC, p.ViewCount DESC) AS FavoriteRank,
      ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC, p.FavoriteCount DESC) AS ViewRank,
      LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore,
      LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS NextPostScore,
      SUM(p.Score) OVER (ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningTotalScore,
      p.CreationDate
    FROM
      Posts p
    WHERE
      p.PostTypeId IN (1, 2) AND p.Score > 0
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      COUNT(DISTINCT p.Id) AS PostCount,
      AVG(p.Score) AS AvgPostScore,
      SUM(p.ViewCount) AS TotalViewCount,
      MAX(p.LastActivityDate) AS LastUserActivity
    FROM
      Users u
      JOIN Posts p
        ON u.Id = p.OwnerUserId
    WHERE
      u.Reputation > 1000
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.UpVotes,
      u.DownVotes
    HAVING
      COUNT(DISTINCT p.Id) > 10
  ),
  AggregatedComments AS (
    SELECT
      c.PostId,
      COUNT(c.Id) AS CommentCountByPost,
      SUM(c.Score) AS TotalCommentScore,
      AVG(CAST(LENGTH(c.Text) AS DECIMAL)) AS AvgCommentLength
    FROM
      Comments c
    WHERE
      c.Score > 0
    GROUP BY
      c.PostId
  ),
  PostAnalysis AS (
    SELECT
      rp.PostId,
      rp.OwnerUserId,
      rp.Title,
      rp.PostTypeId,
      rp.Score,
      rp.FavoriteCount,
      rp.ViewCount,
      rp.AnswerCount,
      rp.CommentCount,
      rp.ClosedDate,
      rp.ScoreRank,
      rp.FavoriteRank,
      rp.ViewRank,
      (rp.NextPostScore - rp.PreviousPostScore) AS ScoreDifference,
      rp.RunningTotalScore,
      CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.FavoriteCount > 100 THEN 'Highly Favorited'
        WHEN rp.ViewCount > 10000 THEN 'Highly Viewed'
        ELSE 'Standard'
      END AS PostStatus,
      COALESCE(ac.CommentCountByPost, 0) AS AggregatedCommentCount,
      COALESCE(ac.TotalCommentScore, 0) AS AggregatedTotalCommentScore,
      COALESCE(ac.AvgCommentLength, 0) AS AggregatedAvgCommentLength,
      CASE
        WHEN rp.Title LIKE '%?%' AND rp.PostTypeId = 1 THEN 'Question Mark Title'
        WHEN rp.Title NOT LIKE '%?%' AND rp.PostTypeId = 1 THEN 'No Question Mark Title'
        ELSE 'Other'
      END AS TitleHasQuestionMark,
      UPPER(SUBSTRING(COALESCE(pht.Comment, ''), 1, 3)) AS FirstThreeCommentChars,
      rp.CreationDate
    FROM
      RankedPosts rp
      LEFT JOIN AggregatedComments ac
        ON rp.PostId = ac.PostId
      LEFT JOIN PostHistory pht
        ON rp.PostId = pht.PostId
        AND pht.PostHistoryTypeId = 10
  )
SELECT
  pa.PostId,
  pa.Title,
  pa.Score,
  pa.ViewRank,
  pa.PostStatus,
  ua.DisplayName AS OwnerDisplayName,
  ua.Reputation AS OwnerReputation,
  ua.AvgPostScore AS OwnerAvgPostScore,
  pa.AggregatedCommentCount,
  pa.AggregatedTotalCommentScore,
  pa.AggregatedAvgCommentLength,
  pa.ScoreDifference,
  pa.RunningTotalScore,
  pa.TitleHasQuestionMark,
  pa.FirstThreeCommentChars,
  CASE
    WHEN pa.ClosedDate IS NOT NULL AND pa.ClosedDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR) THEN 'Old Closed Post'
    WHEN pa.Score > 500 AND pa.ViewRank < 50 THEN 'Popular High Score Post'
    WHEN pa.AggregatedCommentCount > 50 AND pa.AggregatedTotalCommentScore > 100 THEN 'Highly Discussed Post'
    ELSE 'General Post'
  END AS PostCategorization
FROM
  PostAnalysis pa
  JOIN UserActivity ua
    ON pa.OwnerUserId = ua.UserId
WHERE
  pa.Score > 10
  AND pa.ViewCount > 100
ORDER BY
  pa.Score DESC,
  pa.ViewRank,
  ua.Reputation DESC;