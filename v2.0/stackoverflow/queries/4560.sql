-- {"query": "4560.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 809} 
WITH
  HighReputationUsers AS (
    SELECT
      Id,
      DisplayName,
      Reputation,
      (
        SELECT
          COUNT(*)
        FROM
          Posts AS p_inner
        WHERE
          p_inner.OwnerUserId = Users.Id AND p_inner.PostTypeId = 1
      ) AS QuestionCount
    FROM
      Users
    WHERE
      Reputation > 50000
  ),
  RecentQuestions AS (
    SELECT
      Id,
      OwnerUserId,
      Title,
      CreationDate,
      Score,
      AnswerCount,
      Tags
    FROM
      Posts
    WHERE
      PostTypeId = 1
      AND CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
  ),
  QuestionTagCounts AS (
    SELECT
      rq.Id AS QuestionId,
      t.TagName,
      t.Count AS TagTotalCount,
      ROW_NUMBER() OVER (PARTITION BY rq.Id ORDER BY t.Count DESC) AS rn
    FROM
      RecentQuestions AS rq
      CROSS JOIN UNNEST(string_to_array(substring(rq.Tags, 2, length(rq.Tags) - 2), '><')) AS t_array(TagName)
      JOIN Tags AS t
      ON t_array.TagName = t.TagName
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT ph.PostId) AS PostHistoryCount,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 ELSE 0 END) AS BodyEditCount,
      AVG(CASE WHEN c.Score IS NOT NULL THEN c.Score ELSE 0 END) AS AvgCommentScore
    FROM
      Users AS u
      LEFT JOIN PostHistory AS ph
      ON u.Id = ph.UserId
      LEFT JOIN Comments AS c
      ON u.Id = c.UserId AND c.PostId = ph.PostId
    GROUP BY
      u.Id,
      u.DisplayName
  )
SELECT
  hru.DisplayName AS HighRepUser,
  hru.Reputation,
  hru.QuestionCount,
  rq.Title AS RecentQuestionTitle,
  rq.CreationDate AS QuestionCreationDate,
  rq.Score AS QuestionScore,
  COALESCE(rq.AnswerCount, 0) AS AnswerCount,
  COALESCE(qtc.TagName, 'No Tags') AS MostFrequentTag,
  COALESCE(qtc.TagTotalCount, 0) AS TagPostCount,
  ua.PostHistoryCount,
  ua.BodyEditCount,
  ua.AvgCommentScore,
  CASE
    WHEN hru.Id IS NULL THEN 'No High Rep User'
    WHEN rq.OwnerUserId IS NULL THEN 'No Recent Question'
    ELSE 'Active Contributor'
  END AS UserStatus
FROM
  HighReputationUsers AS hru
FULL OUTER JOIN
  RecentQuestions AS rq
  ON hru.Id = rq.OwnerUserId
LEFT JOIN
  QuestionTagCounts AS qtc
  ON rq.Id = qtc.QuestionId
  AND qtc.rn = 1
LEFT JOIN
  UserActivity AS ua
  ON hru.Id = ua.UserId OR rq.OwnerUserId = ua.UserId
WHERE
  ua.PostHistoryCount > 100 OR ua.AvgCommentScore > 5 OR rq.Score > 50
ORDER BY
  hru.Reputation DESC,
  rq.CreationDate DESC;