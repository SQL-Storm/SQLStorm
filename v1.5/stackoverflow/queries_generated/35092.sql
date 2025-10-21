-- {"query": "35092.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 629} 
WITH
  TopAnswerers AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      SUM(CASE WHEN p.Score > 5 THEN 1 ELSE 0 END) AS HighScoreAnswers,
      COUNT(a.Id) AS TotalAnswers,
      AVG(a.Score) AS AvgAnswerScore
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1 -- Questions
    JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2 -- Answers to those questions
    WHERE p.CreationDate >= NOW() - INTERVAL '1 year'
      AND a.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(a.Id) > 50
  ),
  RapidEditors AS (
    SELECT
      ph.UserId AS EditorUserId,
      u.DisplayName AS EditorName,
      COUNT(DISTINCT ph.PostId) AS PostsEdited,
      AVG(EXTRACT(epoch FROM (ph.CreationDate - p.CreationDate))/60) AS AvgMinutesToFirstEdit
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4,5,6) -- Edits
      AND p.CreationDate >= NOW() - INTERVAL '1 year'
      AND ph.CreationDate >= NOW() - INTERVAL '1 year'
      AND ph.Id = (
        SELECT MIN(ph2.Id)
        FROM PostHistory ph2
        WHERE ph2.PostId = ph.PostId AND ph2.PostHistoryTypeId IN (4,5,6)
      )
    GROUP BY ph.UserId, u.DisplayName
    HAVING COUNT(DISTINCT ph.PostId) > 30
  ),
  HotTags AS (
    SELECT
      t.TagName,
      SUM(p.ViewCount) AS TotalViews,
      COUNT(p.Id) AS NumQuestions
    FROM Tags t
    JOIN Posts p ON p.PostTypeId = 1 AND p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE p.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 200
    ORDER BY TotalViews DESC
    LIMIT 10
  )
SELECT
  ta.DisplayName AS TopUser,
  ta.HighScoreAnswers,
  ta.TotalAnswers,
  ta.AvgAnswerScore,
  re.EditorName,
  re.PostsEdited,
  re.AvgMinutesToFirstEdit,
  ht.TagName,
  ht.TotalViews,
  ht.NumQuestions
FROM TopAnswerers ta
LEFT JOIN RapidEditors re ON ta.UserId = re.EditorUserId
CROSS JOIN HotTags ht
ORDER BY ta.HighScoreAnswers DESC, re.PostsEdited DESC NULLS LAST, ht.TotalViews DESC
LIMIT 100;