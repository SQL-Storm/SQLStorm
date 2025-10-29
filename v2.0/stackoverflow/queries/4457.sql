-- {"query": "4457.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1423}
WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.OwnerUserId,
      p.PostTypeId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_post_type,
      AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS avg_score_post_type,
      MAX(p.ViewCount) OVER (PARTITION BY p.PostTypeId) AS max_view_count_post_type,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS prev_day_score,
      LEAD(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS next_day_score
    FROM Posts p
    WHERE
      p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY
  ),
  UserPostStats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_count,
      COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_count,
      SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS total_question_score,
      SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS total_answer_score,
      AVG(p.Score) AS average_score_per_post,
      MAX(u.Reputation) AS max_reputation,
      STRING_AGG(DISTINCT ph.Comment, '; ') AS recent_post_comments
    FROM Users u
    JOIN Posts p
      ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph
      ON p.Id = ph.PostId
      AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 19, 20)
    WHERE
      p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  )
SELECT
  rp.PostId,
  rp.Title AS PostTitle,
  u.DisplayName AS OwnerDisplayName,
  rp.PostTypeId,
  pt.Name AS PostTypeName,
  rp.CreationDate AS PostCreationDate,
  rp.Score AS PostScore,
  rp.ViewCount AS PostViewCount,
  rp.rn_post_type AS RankWithinPostType,
  rp.avg_score_post_type AS AverageScoreForPostType,
  rp.max_view_count_post_type AS MaxViewCountForPostType,
  CASE
    WHEN rp.Score > rp.avg_score_post_type THEN 'Above Average'
    WHEN rp.Score < rp.avg_score_post_type THEN 'Below Average'
    ELSE 'Average'
  END AS ScoreComparison,
  CASE
    WHEN rp.ViewCount = rp.max_view_count_post_type THEN 'Most Viewed'
    ELSE 'Not Most Viewed'
  END AS ViewCountStatus,
  rp.prev_day_score AS PreviousDayScore,
  rp.next_day_score AS NextDayScore,
  CASE
    WHEN rp.Score > rp.prev_day_score AND rp.Score > rp.next_day_score THEN 'Trending Up'
    WHEN rp.Score < rp.prev_day_score AND rp.Score < rp.next_day_score THEN 'Trending Down'
    ELSE 'Stable'
  END AS ScoreTrend,
  COALESCE(ups.question_count, 0) AS UserQuestionCount,
  COALESCE(ups.answer_count, 0) AS UserAnswerCount,
  COALESCE(ups.total_question_score, 0) AS UserTotalQuestionScore,
  COALESCE(ups.total_answer_score, 0) AS UserTotalAnswerScore,
  ups.average_score_per_post AS UserAverageScore,
  ups.max_reputation AS UserMaxReputation,
  CASE
    WHEN ups.recent_post_comments IS NOT NULL THEN 'Has Recent Comments'
    ELSE 'No Recent Comments'
  END AS HasRecentPostComments,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId AND c.Score > 5) AS HighScoreCommentCount,
  (
    SELECT
      COUNT(ph2.Id)
    FROM PostHistory ph2
    WHERE
      ph2.PostId = rp.PostId AND ph2.PostHistoryTypeId = 5
  ) AS BodyEditCount,
  (
    SELECT
      SUM(CASE WHEN ph3.Comment ~ '^[0-9]+$' THEN CAST(ph3.Comment AS BIGINT) ELSE 0 END)
    FROM PostHistory ph3
    WHERE
      ph3.PostId = rp.PostId AND ph3.PostHistoryTypeId = 10
  ) AS TotalCloseVoteComments,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostLinks pl
      WHERE
        pl.PostId = rp.PostId AND pl.LinkTypeId = 3
    ) THEN 'Is Duplicate'
    ELSE 'Not A Duplicate'
  END AS DuplicateStatus
FROM RankedPosts rp
LEFT JOIN Users u
  ON rp.OwnerUserId = u.Id
LEFT JOIN PostTypes pt
  ON rp.PostTypeId = pt.Id
LEFT JOIN UserPostStats ups
  ON rp.OwnerUserId = ups.UserId
WHERE
  rp.rn_post_type <= 100
  AND rp.Score > 0
  AND rp.ViewCount > 1000
  AND (
    rp.Title LIKE '%SQL%' OR rp.Title LIKE '%Performance%'
  )
ORDER BY
  rp.PostTypeId,
  rp.rn_post_type;