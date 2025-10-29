-- {"query": "5892.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 842} 
WITH
-- sample derived dataset for benchmarking
RecentQuestions AS (
  SELECT
    p.Id AS PostId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    -- approximate length of Body for heavier text processing
    LENGTH(p.Body) AS BodyLength,
    -- number of related posts via PostLinks
    COALESCE(pl.LinkCount,0) AS RelatedCount
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS LinkCount
    FROM PostLinks
    GROUP BY PostId
  ) pl ON pl.PostId = p.Id
  WHERE p.PostTypeId = 1 -- questions
    AND p.ClosedDate IS NULL
),
Numbered AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY CreationDate DESC) AS rn_by_owner,
    RANK() OVER (ORDER BY BodyLength DESC, Score DESC) AS rank_by_len_score
  FROM RecentQuestions
),
Aggregated AS (
  SELECT
    OwnerUserId,
    COUNT(*) AS QuestionCount,
    SUM(Score) AS TotalScore,
    AVG(BodyLength) AS AvgBodyLen,
    MAX(CreationDate) AS LastCreated
  FROM Numbered
  GROUP BY OwnerUserId
),
Windowed AS (
  SELECT
    n.*,
    a.QuestionCount,
    a.TotalScore,
    a.AvgBodyLen,
    a.LastCreated,
    -- running total of questions per owner to stress window functions
    SUM(1) OVER (PARTITION BY n.OwnerUserId ORDER BY n.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningCount
  FROM Numbered n
  LEFT JOIN Aggregated a ON a.OwnerUserId = n.OwnerUserId
),
ComplexFilter AS (
  SELECT
    w.*,
    -- complex predicate with NULL-aware logic and computed expressions
    CASE
      WHEN w.BodyLength > 1000 THEN 1
      WHEN w.BodyLength IS NULL THEN 0
      ELSE 2
    END AS LengthBucket,
    -- derived tag-based match count
    (SELECT COUNT(*) FROM unnest(string_to_array(w.Tags, '>') ) AS t) AS TagFragmentCount
  FROM Windowed w
),
Final AS (
  SELECT
    cf.*,
    -- correlate with votes to simulate heavier workload
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = cf.PostId AND v.VoteTypeId IN (2,3)) AS VoteCount68,
    (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = cf.PostId) AS LastVoteDate,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = cf.PostId AND v.BountyAmount IS NOT NULL) AS AvgBounty
  FROM ComplexFilter cf
  LEFT JOIN PostLinks pl ON pl.PostId = cf.PostId
  LEFT JOIN Posts p2 ON p2.Id = cf.PostId
  -- optional join to trigger outer-join behavior and NULL handling
  LEFT JOIN Tags t ON t.ExcerptPostId = cf.PostId
  WHERE 1=1
    -- elaborate predicate combining numeric, text and NULL logic
    AND (
      cf.Score IS NULL OR cf.Score >= 0
    )
    AND (
      cf.OwnerUserId IS NULL OR cf.OwnerUserId IN (SELECT Id FROM Users WHERE Reputation > 100)
    )
)
SELECT
  *
FROM Final
ORDER BY LastActivityDate DESC
LIMIT 100;