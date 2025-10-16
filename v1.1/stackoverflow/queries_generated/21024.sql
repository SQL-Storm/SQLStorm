-- {"query": "21024.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1531} 

WITH ActiveUsers AS (
  SELECT 
    u.Id AS UserId,
    u.Reputation,
    u.CreationDate,
    u.Location,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
    SUM(p.Score) AS TotalScore,
    AVG(p.Score) AS AvgPostScore
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id 
    AND p.CreationDate > CURRENT_DATE - INTERVAL '1 year'
  WHERE u.Reputation >= 100 
    AND u.LastAccessDate > CURRENT_DATE - INTERVAL '6 months'
  GROUP BY u.Id, u.Reputation, u.CreationDate, u.Location
  HAVING COUNT(p.Id) > 0
),
TagStats AS (
  SELECT 
    t.TagName,
    t.Count AS TotalPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1,4,7) 
                       THEN ph.PostId END) AS TitleEdits,
    AVG(EXTRACT(EPOCH FROM (ph.CreationDate - p.CreationDate))/3600) AS AvgHoursToFirstEdit,
    STRING_AGG(DISTINCT COALESCE(u.DisplayName, 'Anonymous'), ', ') AS TopEditors
  FROM Tags t
  INNER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id 
    AND ph.PostHistoryTypeId IN (1,4,7)
    AND ph.CreationDate > p.CreationDate
  LEFT JOIN Users u ON u.Id = ph.UserId
  WHERE t.Count > 50
    AND p.PostTypeId = 1
    AND p.ClosedDate IS NULL
  GROUP BY t.TagName, t.Count
),
CommunityActivity AS (
  SELECT 
    YEAR(p.CreationDate) AS Year,
    MONTH(p.CreationDate) AS Month,
    pt.Name AS PostType,
    COUNT(*) AS PostCount,
    AVG(p.ViewCount) AS AvgViews,
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositivePosts,
    COUNT(DISTINCT p.OwnerUserId) AS ActiveUsersThisPeriod,
    FIRST_VALUE(p.Title) OVER (
      PARTITION BY YEAR(p.CreationDate), MONTH(p.CreationDate), pt.Name 
      ORDER BY p.ViewCount DESC 
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS MostViewedTitle
  FROM Posts p
  INNER JOIN PostTypes pt ON pt.Id = p.PostTypeId
  WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    AND p.DeletionDate IS NULL
  GROUP BY YEAR(p.CreationDate), MONTH(p.CreationDate), pt.Name
),
VotePatterns AS (
  SELECT 
    v.PostId,
    p.Title,
    p.Score AS PostScore,
    COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVotes,
    COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVotes,
    COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) - 
    COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS NetVotes,
    RANK() OVER (ORDER BY 
      (COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END)::float / 
       NULLIF(COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END), 0)) DESC
    ) AS ControversyRank,
    LAG(p.Score) OVER (
      PARTITION BY p.PostTypeId 
      ORDER BY v.CreationDate
    ) AS PreviousPostScore
  FROM Votes v
  INNER JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  INNER JOIN Posts p ON p.Id = v.PostId
  WHERE v.CreationDate > CURRENT_DATE - INTERVAL '1 year'
    AND vt.Name IN ('UpMod', 'DownMod')
  GROUP BY v.PostId, p.Title, p.Score
  HAVING COUNT(*) > 5
)
SELECT 
  au.UserId,
  au.DisplayName,
  au.Location,
  au.QuestionCount,
  au.AnswerCount,
  au.TotalScore,
  ts.TagName AS PrimaryTag,
  ca.Year,
  ca.Month,
  ca.PostCount AS MonthlyPosts,
  vp.NetVotes,
  vp.ControversyRank,
  CASE 
    WHEN vp.DownVotes > vp.UpVotes * 0.5 THEN 'Controversial'
    WHEN vp.UpVotes > 100 THEN 'Popular'
    WHEN au.Reputation > 10000 AND au.AnswerCount > au.QuestionCount * 2 THEN 'Answer Specialist'
    ELSE 'Regular'
  END AS UserCategory,
  COALESCE(vp.MostViewedTitle, 'No standout post') AS StandoutPost,
  LENGTH(COALESCE(p.Body, '')) > 1000 AS HasLongFormContent,
  (au.TotalScore::float / NULLIF(au.QuestionCount + au.AnswerCount, 0)) AS ScorePerPost,
  CONCAT(
    au.Location, 
    CASE WHEN au.Location IS NOT NULL AND au.Location != '' THEN ', ' ELSE '' END,
    EXTRACT(YEAR FROM AGE(CURRENT_DATE, au.CreationDate))::text, ' years active'
  ) AS UserProfileSummary
FROM ActiveUsers au
LEFT JOIN (
  SELECT 
    p.OwnerUserId,
    SUBSTRING(p.Tags FROM 2 FOR POSITION('><' IN p.Tags)-2) AS FirstTag,
    COUNT(*) as TagUsage
  FROM Posts p 
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL 
    AND LENGTH(p.Tags) > 0
  GROUP BY p.OwnerUserId, FirstTag
  ORDER BY TagUsage DESC
) first_tag ON first_tag.OwnerUserId = au.UserId
INNER JOIN TagStats ts ON ts.TagName = first_tag.FirstTag
LEFT JOIN CommunityActivity ca ON ca.Year = EXTRACT(YEAR FROM au.CreationDate)
  AND ca.Month = EXTRACT(MONTH FROM au.CreationDate)
LEFT JOIN VotePatterns vp ON vp.PostId IN (
  SELECT p.Id 
  FROM Posts p 
  WHERE p.OwnerUserId = au.UserId 
    AND p.CreationDate > CURRENT_DATE - INTERVAL '6 months'
  LIMIT 1
)
LEFT JOIN Posts p ON p.OwnerUserId = au.UserId 
  AND p.PostTypeId = 1
  AND p.CreationDate = (
    SELECT MAX(p2.CreationDate) 
    FROM Posts p2 
    WHERE p2.OwnerUserId = au.UserId AND p2.PostTypeId = 1
  )
WHERE au.QuestionCount + au.AnswerCount >= 3
  AND (vp.NetVotes IS NULL OR ABS(vp.NetVotes) < 50)
  AND ts.TotalPosts > 100
  AND NOT (au.Location ILIKE '%spam%' OR au.DisplayName ILIKE '%bot%')
ORDER BY au.TotalScore DESC, vp.ControversyRank ASC
LIMIT 100;
