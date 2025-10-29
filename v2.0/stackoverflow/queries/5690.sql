-- {"query": "5690.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 910}
WITH
  RecentUsers AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.LastAccessDate,
      ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
    FROM Users u
    WHERE u.LastAccessDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180' DAY
  ),
  ActiveQuestions AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.Score,
      p.ViewCount,
      p.CreationDate,
      p.LastEditDate,
      p.OwnerUserId,
      p.Tags,
      p.AnswerCount,
      CASE
        WHEN p.Score > 0 THEN 'positive'
        WHEN p.Score < 0 THEN 'negative'
        ELSE 'neutral'
      END AS ScoreCategory
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.LastEditDate IS NOT NULL
      AND p.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '365' DAY
      AND (p.Score >= 0 OR p.ViewCount > 100)
  ),
  PostLinksCounts AS (
    SELECT
      aq.PostId,
      COALESCE((
        SELECT COUNT(*) FROM PostLinks pl
        WHERE pl.PostId = aq.PostId
          AND pl.LinkTypeId IN (1, 3)
      ), 0) AS RelatedLinkCount
    FROM ActiveQuestions aq
  ),
  DailyViews AS (
    SELECT
      a.PostId,
      CAST(a.CreationDate AS DATE) AS TheDay,
      SUM(a.ViewCount) OVER (PARTITION BY a.PostId ORDER BY a.CreationDate
                             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeViews
    FROM ActiveQuestions a
  ),
  PostVoteStats AS (
    SELECT
      aq.PostId,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
      SUM(CASE WHEN v.VoteTypeId = 6 THEN 1 ELSE 0 END) AS CloseVotes
    FROM ActiveQuestions aq
    LEFT JOIN Posts p ON p.Id = aq.PostId
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY aq.PostId
  ),
  UserPostActivity AS (
    SELECT
      ru.UserId,
      ru.DisplayName,
      ru.Reputation,
      ap.Id AS PostId,
      ap.Title,
      ap.Score,
      ap.ViewCount,
      pv.UpVotes,
      pv.DownVotes,
      pv.CloseVotes,
      dl.RelatedLinkCount,
      dv.CumulativeViews
    FROM RecentUsers ru
    LEFT JOIN Posts ap ON ap.OwnerUserId = ru.UserId
    LEFT JOIN PostVoteStats pv ON pv.PostId = ap.Id
    LEFT JOIN PostLinksCounts dl ON dl.PostId = ap.Id
    LEFT JOIN DailyViews dv ON dv.PostId = ap.Id
    WHERE ru.rn <= 50
  )
SELECT
  UPPER('Benchmark: Complex Social Post Landscape') AS BenchmarkLabel,
  SUM(COALESCE(upa.UpVotes, 0) + COALESCE(upa.DownVotes, 0) + COALESCE(upa.CloseVotes, 0)) AS TotalVotesConsidered,
  COUNT(DISTINCT upa.PostId) AS DistinctPostsInScope,
  AVG(COALESCE(aq.Score, 0)) AS AvgPostScore,
  MAX(COALESCE(aq.ViewCount, 0)) AS MaxViewsOnPost,
  SUM(COALESCE(dv.CumulativeViews, 0)) AS TotalCumulativeViews
FROM UserPostActivity upa
LEFT JOIN ActiveQuestions aq ON aq.PostId = upa.PostId
LEFT JOIN DailyViews dv ON dv.PostId = upa.PostId
GROUP BY UPPER('Benchmark: Complex Social Post Landscape');