-- {"query": "4211.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1904} 

WITH
  RelevantPosts AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.AnswerCount,
      p.FavoriteCount,
      p.ClosedDate,
      p.CommunityOwnedDate,
      CASE WHEN p.PostTypeId = 1 THEN pt.Name ELSE 'N/A' END AS PostTypeName,
      CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN COALESCE(cr.Name, 'Unknown') ELSE 'N/A' END AS CloseReason,
      u.DisplayName AS OwnerDisplayName,
      u.Reputation AS OwnerReputation,
      CASE WHEN p.LastEditDate > p.CreationDate THEN DATEDIFF(minute, p.CreationDate, p.LastEditDate) ELSE 0 END AS EditLagMinutes,
      LEN(p.Title) AS TitleLength,
      LEN(p.Tags) AS TagsLength,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
      COUNT(DISTINCT c.Id) AS CommentCountActual
    FROM Posts AS p
    INNER JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    LEFT JOIN CloseReasonTypes AS cr
      ON p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL AND CAST(p.Comment AS INT) = cr.Id -- Assuming 'Comment' stores CloseReasonId for closed posts
    WHERE
      p.CreationDate >= DATEADD(year, -2, GETDATE())
      AND p.PostTypeId IN (1, 2)
    GROUP BY
      p.Id,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.FavoriteCount,
      p.ClosedDate,
      p.CommunityOwnedDate,
      pt.Name,
      cr.Name,
      u.DisplayName,
      u.Reputation,
      p.LastEditDate,
      p.Title,
      p.Tags,
      p.Comment
  ),
  PostPerformance AS (
    SELECT
      rp.PostId,
      rp.PostTypeName,
      rp.OwnerDisplayName,
      rp.OwnerReputation,
      rp.PostCreationDate,
      rp.PostScore,
      rp.PostViewCount,
      rp.AnswerCount,
      rp.FavoriteCount,
      rp.EditLagMinutes,
      rp.CloseReason,
      rp.UpVotes,
      rp.DownVotes,
      rp.CommentCountActual,
      rp.TitleLength,
      rp.TagsLength,
      ROW_NUMBER() OVER (ORDER BY rp.PostScore DESC, rp.PostViewCount DESC) AS ScoreRank,
      LAG(rp.PostScore, 1, 0) OVER (ORDER BY rp.PostCreationDate) AS PreviousDayScore,
      CASE WHEN rp.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      CAST(rp.PostCreationDate AS DATE) AS PostDateOnly,
      CASE
        WHEN rp.OwnerReputation >= 100000 THEN 'High'
        WHEN rp.OwnerReputation >= 10000 THEN 'Medium'
        ELSE 'Low'
      END AS ReputationTier,
      RPAD('★', rp.FavoriteCount % 5 + 1, '☆') AS FavoriteIndicator,
      CONCAT(
        rp.PostTypeName,
        '-',
        COALESCE(rp.CloseReason, 'Open')
      ) AS PostStatus,
      CASE
        WHEN rp.EditLagMinutes > 60 THEN 'HighLag'
        WHEN rp.EditLagMinutes > 15 THEN 'MediumLag'
        ELSE 'LowLag'
      END AS EditLagCategory,
      CASE
        WHEN rp.CommunityOwnedDate IS NOT NULL THEN 'Community'
        WHEN rp.OwnerUserId = -1 THEN 'Community'
        ELSE 'UserOwned'
      END AS OwnershipType,
      rp.PostViewCount * 1.0 / NULLIF(rp.AnswerCount, 0) AS AvgViewsPerAnswer,
      rp.UpVotes - rp.DownVotes AS NetVotes,
      CASE
        WHEN rp.PostScore > 50 AND rp.AnswerCount > 10 THEN 'HighPerforming'
        WHEN rp.PostScore > 10 AND rp.AnswerCount > 3 THEN 'MediumPerforming'
        ELSE 'Standard'
      END AS PerformanceSegment
    FROM RelevantPosts AS rp
    WHERE
      rp.OwnerUserId IS NOT NULL AND rp.OwnerUserId <> -1
  )
SELECT
  pp.PostId,
  pp.PostTypeName,
  pp.OwnerDisplayName,
  pp.OwnerReputation,
  pp.PostCreationDate,
  pp.PostScore,
  pp.PostViewCount,
  pp.AnswerCount,
  pp.FavoriteCount,
  pp.EditLagMinutes,
  pp.CloseReason,
  pp.UpVotes,
  pp.DownVotes,
  pp.CommentCountActual,
  pp.ScoreRank,
  pp.PreviousDayScore,
  pp.IsClosed,
  pp.PostDateOnly,
  pp.ReputationTier,
  pp.FavoriteIndicator,
  pp.PostStatus,
  pp.EditLagCategory,
  pp.OwnershipType,
  pp.AvgViewsPerAnswer,
  pp.NetVotes,
  pp.PerformanceSegment,
  (
    SELECT
      COUNT(*)
    FROM Posts AS p2
    WHERE
      p2.OwnerUserId = (
        SELECT
          OwnerUserId
        FROM Posts AS p1
        WHERE
          p1.Id = pp.PostId
      ) AND p2.CreationDate < pp.PostCreationDate
  ) AS PreviousPostsByOwner,
  CASE
    WHEN pp.PostScore < 0 THEN 'NegativeScore'
    WHEN pp.PostScore BETWEEN 0 AND 10 THEN 'LowScore'
    WHEN pp.PostScore BETWEEN 11 AND 100 THEN 'MediumScore'
    ELSE 'HighScore'
  END AS ScoreBracket,
  COALESCE(pp.TitleLength, 0) + COALESCE(pp.TagsLength, 0) AS TotalMetadataLength,
  IIF(pp.FavoriteCount > 0, 'Favorited', 'NotFavorited') AS IsFavorited,
  CASE
    WHEN pp.PostTypeName = 'Question' AND pp.AnswerCount IS NULL THEN 'AnswerCountMissing'
    WHEN pp.PostTypeName = 'Question' AND pp.AnswerCount = 0 THEN 'NoAnswers'
    ELSE 'HasAnswers'
  END AS AnswerStatus,
  (
    SELECT
      MAX(CreationDate)
    FROM Comments AS c
    WHERE
      c.PostId = pp.PostId
  ) AS LastCommentDate,
  CASE
    WHEN pp.PostTypeName = 'Question' AND pp.ClosedDate IS NOT NULL AND pp.CloseReason IN ('Off-topic', 'Not a real question', 'Too localized', 'Subjective and argumentative') THEN 'Potentially PoorlyClosed'
    WHEN pp.PostTypeName = 'Question' AND pp.ClosedDate IS NOT NULL AND pp.CloseReason = 'Duplicate' THEN 'DuplicateClose'
    ELSE 'OtherCloseOrOpen'
  END AS CloseClassification
FROM PostPerformance AS pp
WHERE
  pp.OwnerReputation > 100
  AND pp.PostScore > 0
  AND pp.PostViewCount > 100
  AND pp.PostCreationDate BETWEEN '2022-01-01' AND '2023-12-31'
ORDER BY
  pp.PostScore DESC,
  pp.PostViewCount DESC
LIMIT 1000;
