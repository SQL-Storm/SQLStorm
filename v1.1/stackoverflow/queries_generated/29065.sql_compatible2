WITH RankedPosts AS (
  SELECT 
    p.Id,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS ScoreRank,
    DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreDenseRank,
    NTILE(10) OVER (ORDER BY p.Score DESC) AS ScoreQuartile
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
  SELECT 
    u.Id AS UserId,
    u.Reputation,
    u.DisplayName,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(p.Score) AS TotalScore,
    AVG(p.Score) AS AvgScore,
    MAX(p.CreationDate) AS LastPostDate,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionCount,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswerCount
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
  SELECT 
    t.TagName,
    t.Count,
    t.IsRequired,
    t.IsModeratorOnly,
    COALESCE(SUM(p.Score), 0) AS TagTotalScore,
    COALESCE(AVG(p.Score), 0) AS TagAvgScore,
    RANK() OVER (ORDER BY t.Count DESC) AS TagRank,
    CASE 
      WHEN t.Count > 1000 THEN 'High'
      WHEN t.Count > 100 THEN 'Medium'
      WHEN t.Count > 10 THEN 'Low'
      ELSE 'Very Low'
    END AS TagPopularityLevel
  FROM Tags t
  LEFT JOIN Posts p ON p.Tags IS NOT NULL AND p.Tags LIKE '%' || t.TagName || '%'
  WHERE t.TagName IS NOT NULL
  GROUP BY t.TagName, t.Count, t.IsRequired, t.IsModeratorOnly
),
ComplexPostAnalysis AS (
  SELECT 
    rp.Id,
    rp.PostTypeId,
    rp.Score,
    rp.ViewCount,
    rp.Title,
    rp.Tags,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.ScoreRank,
    rp.ScoreDenseRank,
    rp.ScoreQuartile,
    CASE 
      WHEN rp.Score > 100 THEN 'Highly Upvoted'
      WHEN rp.Score > 50 THEN 'Upvoted'
      WHEN rp.Score > 0 THEN 'Neutral'
      WHEN rp.Score < 0 THEN 'Downvoted'
      ELSE 'No Votes'
    END AS VoteStatus,
    CASE 
      WHEN rp.AnswerCount > 10 THEN 'Highly Active'
      WHEN rp.AnswerCount > 5 THEN 'Active'
      WHEN rp.AnswerCount > 0 THEN 'Slightly Active'
      ELSE 'Inactive'
    END AS ActivityLevel,
    (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - rp.CreationDate) AS IntervalSinceCreation,
    (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - rp.CreationDate)) / 86400) AS DaysSinceCreation,
    COALESCE(rp.CommentCount, 0) AS Comments,
    COALESCE(rp.FavoriteCount, 0) AS Favorites
  FROM RankedPosts rp
  WHERE rp.Score IS NOT NULL
),
ComprehensiveUserPostStats AS (
  SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.PostCount,
    us.TotalScore,
    us.AvgScore,
    us.LastPostDate,
    us.QuestionCount,
    us.AnswerCount,
    CASE 
      WHEN us.PostCount > 100 THEN 'Expert'
      WHEN us.PostCount > 50 THEN 'Regular'
      WHEN us.PostCount > 10 THEN 'Casual'
      ELSE 'Beginner'
    END AS PostingLevel,
    CASE 
      WHEN us.TotalScore > 5000 THEN 'Veteran'
      WHEN us.TotalScore > 1000 THEN 'Experienced'
      WHEN us.TotalScore > 100 THEN 'Intermediate'
      ELSE 'Novice'
    END AS ScoreLevel
  FROM UserStats us
  WHERE us.Reputation IS NOT NULL
),
PostTags AS (
  -- Portable approach: split tags using generic string functions where available.
  -- Use recursive split for dialects without regexp_split_to_table if needed; here assume standard split via UNNEST of a string_to_array where available.
  -- Fallback using simple parsing: treat tags as delimited by '<' and '>' and split by those characters.
  SELECT
    rp.Id AS PostId,
    TRIM(tag) AS TagName
  FROM RankedPosts rp
  JOIN (
    SELECT rp2.Id AS pid, TRIM(x) AS tag
    FROM RankedPosts rp2,
    LATERAL (
      SELECT value AS x FROM (
        SELECT UNNEST(string_to_array(REGEXP_REPLACE(rp2.Tags, '^<|>$', '', 'g'), '>')) AS value
      ) s
    ) t
    WHERE rp2.Tags IS NOT NULL
  ) split ON split.pid = rp.Id
  WHERE rp.Tags IS NOT NULL
),
FinalAnalysis AS (
  SELECT 
    cpa.Id,
    cpa.PostTypeId,
    cpa.Score,
    cpa.ViewCount,
    cpa.Title,
    cpa.Tags,
    cpa.OwnerUserId,
    cpa.CreationDate,
    cpa.ScoreRank,
    cpa.ScoreDenseRank,
    cpa.ScoreQuartile,
    cpa.VoteStatus,
    cpa.ActivityLevel,
    CAST(cpa.DaysSinceCreation AS INTEGER) AS DaysSinceCreation,
    cpa.Comments,
    cpa.Favorites,
    cus.UserId,
    cus.DisplayName,
    cus.Reputation,
    cus.PostCount,
    cus.TotalScore,
    cus.AvgScore,
    cus.LastPostDate,
    cus.QuestionCount,
    cus.AnswerCount,
    cus.PostingLevel,
    cus.ScoreLevel,
    ta.TagName,
    ta.Count AS TagCount,
    ta.TagTotalScore,
    ta.TagAvgScore,
    ta.TagPopularityLevel,
    CASE 
      WHEN ta.TagName IS NOT NULL THEN 'Tagged'
      ELSE 'Untagged'
    END AS TagStatus,
    CASE 
      WHEN cus.PostingLevel = 'Expert' AND ta.Count > 500 THEN 'High Impact Expert'
      WHEN cus.PostingLevel = 'Expert' THEN 'Expert'
      WHEN cus.ScoreLevel = 'Veteran' AND ta.Count > 250 THEN 'High Impact Veteran'
      WHEN cus.ScoreLevel = 'Veteran' THEN 'Veteran'
      ELSE 'Regular User'
    END AS UserTagImpactLevel
  FROM ComplexPostAnalysis cpa
  LEFT JOIN ComprehensiveUserPostStats cus ON cpa.OwnerUserId = cus.UserId
  LEFT JOIN PostTags pt ON pt.PostId = cpa.Id
  LEFT JOIN TagAnalysis ta ON ta.TagName = pt.TagName
  WHERE 
    (ta.TagPopularityLevel IN ('High', 'Medium') OR ta.TagName IS NULL)
    AND (cus.PostingLevel IN ('Expert', 'Regular') OR cus.UserId IS NULL)
    AND cpa.ScoreQuartile IN (1, 2, 3)
)
SELECT 
  fa.Id,
  fa.PostTypeId,
  fa.Score,
  fa.ViewCount,
  fa.Title,
  fa.Tags,
  fa.OwnerUserId,
  fa.CreationDate,
  fa.ScoreRank,
  fa.ScoreDenseRank,
  fa.ScoreQuartile,
  fa.VoteStatus,
  fa.ActivityLevel,
  fa.DaysSinceCreation,
  fa.Comments,
  fa.Favorites,
  fa.UserId,
  fa.DisplayName,
  fa.Reputation,
  fa.PostCount,
  fa.TotalScore,
  fa.AvgScore,
  fa.LastPostDate,
  fa.QuestionCount,
  fa.AnswerCount,
  fa.PostingLevel,
  fa.ScoreLevel,
  fa.TagName,
  fa.TagCount,
  fa.TagTotalScore,
  fa.TagAvgScore,
  fa.TagPopularityLevel,
  fa.TagStatus,
  fa.UserTagImpactLevel,
  LAG(fa.Score) OVER (ORDER BY fa.Score DESC) AS PreviousScore,
  LEAD(fa.Score) OVER (ORDER BY fa.Score DESC) AS NextScore,
  RANK() OVER (PARTITION BY fa.PostingLevel ORDER BY fa.Score DESC) AS LevelScoreRank,
  PERCENT_RANK() OVER (ORDER BY fa.Score) AS PercentileRank
FROM FinalAnalysis fa
WHERE fa.Score IS NOT NULL
  AND (fa.TagStatus = 'Tagged' OR fa.TagName IS NULL)
  AND fa.DaysSinceCreation BETWEEN 30 AND 730
ORDER BY fa.Score DESC, fa.Reputation DESC
LIMIT 1000;