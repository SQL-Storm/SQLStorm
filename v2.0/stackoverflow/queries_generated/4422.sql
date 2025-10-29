-- {"query": "4422.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1476} 

WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ViewCount,
      p.OwnerUserId,
      pt.Name AS PostTypeName,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.OwnerUserId
        ORDER BY
          p.CreationDate DESC
      ) AS rn
    FROM
      Posts AS p
      JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    WHERE
      p.CreationDate > '2023-01-01'
      AND pt.Name IN ('Question', 'Answer')
  ),
  UserEngagement AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.UpVotes,
      u.DownVotes,
      u.Views AS UserViews,
      COUNT(DISTINCT c.Id) AS CommentCount,
      COUNT(DISTINCT v.Id) AS VoteCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM
      Users AS u
      LEFT JOIN Comments AS c ON u.Id = c.UserId
      LEFT JOIN Votes AS v ON u.Id = v.UserId
    WHERE
      u.CreationDate > '2022-01-01'
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.UpVotes,
      u.DownVotes,
      u.Views
  ),
  PostStats AS (
    SELECT
      rp.PostId,
      rp.Title,
      rp.PostTypeName,
      rp.Score,
      rp.AnswerCount,
      rp.CommentCount AS PostCommentCount,
      rp.FavoriteCount,
      rp.ViewCount,
      ue.DisplayName AS OwnerDisplayName,
      ue.Reputation AS OwnerReputation,
      ue.CommentCount AS OwnerCommentCount,
      ue.VoteCount AS OwnerVoteCount,
      (rp.Score * 1.0 / NULLIF(rp.ViewCount, 0)) AS ScorePerView,
      (rp.AnswerCount * 1.0 / NULLIF(rp.FavoriteCount, 0)) AS AnswersPerFavorite,
      CASE
        WHEN rp.PostTypeName = 'Question' THEN 'Q'
        WHEN rp.PostTypeName = 'Answer' THEN 'A'
        ELSE 'O'
      END AS PostTypeShort,
      CASE
        WHEN rp.Score > 100 THEN 'High'
        WHEN rp.Score > 10 THEN 'Medium'
        ELSE 'Low'
      END AS ScoreBucket,
      CASE
        WHEN rp.AnswerCount > 5 THEN 'Many Answers'
        WHEN rp.AnswerCount > 0 THEN 'Some Answers'
        ELSE 'No Answers'
      END AS AnswerCategory,
      rp.rn AS UserPostRank
    FROM
      RankedPosts AS rp
      LEFT JOIN UserEngagement AS ue ON rp.OwnerUserId = ue.UserId
    WHERE
      rp.rn <= 10
  )
SELECT
  ps.PostId,
  ps.Title,
  ps.PostTypeName,
  ps.Score,
  ps.AnswerCount,
  ps.PostCommentCount,
  ps.FavoriteCount,
  ps.ViewCount,
  ps.OwnerDisplayName,
  ps.OwnerReputation,
  ps.OwnerCommentCount,
  ps.OwnerVoteCount,
  ps.ScorePerView,
  ps.AnswersPerFavorite,
  ps.PostTypeShort,
  ps.ScoreBucket,
  ps.AnswerCategory,
  ps.UserPostRank,
  CASE
    WHEN ps.OwnerReputation > 50000 AND ps.Score > 500 THEN 'Top Contributor - Popular Post'
    WHEN ps.OwnerReputation > 10000 AND ps.Score > 100 THEN 'Experienced Contributor - Good Post'
    WHEN ps.OwnerReputation > 1000 AND ps.Score > 10 THEN 'Intermediate Contributor - Average Post'
    WHEN ps.OwnerReputation IS NULL THEN 'Unknown Owner'
    ELSE 'Newer Contributor - Basic Post'
  END AS ContributionLevel,
  COALESCE(ps.ViewCount, 0) AS SafeViewCount,
  CASE
    WHEN ps.OwnerDisplayName LIKE '%[deleted]%' THEN TRUE
    ELSE FALSE
  END AS IsDisplayNameDeleted,
  CASE
    WHEN ps.OwnerReputation BETWEEN 0 AND 1000 THEN 'Bronze Tier'
    WHEN ps.OwnerReputation BETWEEN 1001 AND 10000 THEN 'Silver Tier'
    WHEN ps.OwnerReputation BETWEEN 10001 AND 100000 THEN 'Gold Tier'
    ELSE 'Platinum Tier'
  END AS ReputationTier,
  LENGTH(ps.Title) AS TitleLength,
  SUBSTRING(ps.Title FROM 1 FOR 10) AS TitlePrefix,
  CASE
    WHEN ps.OwnerDisplayName IS NOT NULL THEN UPPER(ps.OwnerDisplayName)
    ELSE 'ANONYMOUS'
  END AS UpperOwnerDisplayName,
  CASE
    WHEN ps.AnswerCount > 0 THEN ps.AnswerCount * LOG(ps.ViewCount + 1)
    ELSE 0
  END AS WeightedAnswerScore,
  ph.PostHistoryTypeId,
  ph.Comment AS PostHistoryComment,
  ph.Text AS PostHistoryText
FROM
  PostStats AS ps
  LEFT OUTER JOIN PostHistory AS ph ON ps.PostId = ph.PostId
  AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13, 14, 15, 16, 19, 20, 24, 33, 34, 35, 36)
WHERE
  ps.OwnerReputation > 0
  OR ps.PostId IS NOT NULL
ORDER BY
  ps.Score DESC,
  ps.ViewCount DESC
LIMIT 100;
