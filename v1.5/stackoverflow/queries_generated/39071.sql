-- {"query": "39071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2803} 

WITH
-- extract questions with parsed tag arrays
Questions AS (
  SELECT
    p.Id,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><') AS TagArray
  FROM Posts p
  WHERE p.PostTypeId = 1
),
-- one row per question/tag
QuestionTags AS (
  SELECT
    q.Id         AS QuestionId,
    tag
  FROM Questions q
  CROSS JOIN unnest(q.TagArray) AS t(tag)
),
-- monthly stats per tag
MonthlyStats AS (
  SELECT
    date_trunc('month', q.CreationDate) AS Month,
    qt.tag,
    count(DISTINCT qt.QuestionId) AS QuestionsPosted,
    sum(q.Score) AS TotalScore
  FROM QuestionTags qt
  JOIN Questions q ON q.Id = qt.QuestionId
  GROUP BY 1,2
),
-- rank tags by volume and compute prior-month values
RankedTags AS (
  SELECT
    Month,
    tag,
    QuestionsPosted,
    TotalScore,
    rank()          OVER (PARTITION BY Month ORDER BY QuestionsPosted DESC) AS TagRank,
    lag(QuestionsPosted)
      OVER (PARTITION BY tag   ORDER BY Month)            AS PrevMonthCount
  FROM MonthlyStats
),
-- count edits per question
EditCounts AS (
  SELECT
    ph.PostId   AS QuestionId,
    count(*)    AS EditCount
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4,5,6)
  GROUP BY ph.PostId
),
-- aggregate votes per question
VoteStats AS (
  SELECT
    v.PostId AS QuestionId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) AS UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) AS DownVotes
  FROM Votes v
  GROUP BY v.PostId
),
-- basic user Q/A aggregates
UserAggregates AS (
  SELECT
    p.OwnerUserId                AS UserId,
    count(*) FILTER (WHERE p.PostTypeId = 1) AS QCount,
    count(*) FILTER (WHERE p.PostTypeId = 2) AS ACount,
    avg(p.Score)   FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore
  FROM Posts p
  WHERE p.PostTypeId IN (1,2)
  GROUP BY p.OwnerUserId
),
-- collect each user's badges history as JSON
TopBadges AS (
  SELECT
    b.UserId,
    json_agg(
      json_build_object('Badge',b.Name,'Date',b.Date)
      ORDER BY b.Date DESC
    ) AS Badges
  FROM Badges b
  GROUP BY b.UserId
),
-- final summary for top tags each month
Final AS (
  SELECT
    rt.Month,
    rt.tag,
    rt.QuestionsPosted,
    rt.PrevMonthCount,
    (rt.QuestionsPosted - coalesce(rt.PrevMonthCount,0)) AS Growth,
    count(DISTINCT q.Id)          AS DistinctQuestions,
    avg(coalesce(ec.EditCount,0)) AS AvgEdits,
    sum(coalesce(vs.UpVotes,0))   AS TotalUpVotes,
    sum(coalesce(vs.DownVotes,0)) AS TotalDownVotes,
    avg(ua.AvgAnswerScore)        AS AvgAuthorAnswerScore,
    json_agg(
      DISTINCT json_build_object(
        'User', u.DisplayName,
        'Reputation', u.Reputation,
        'Badges', tb.Badges
      )
    ) AS TopContributors
  FROM RankedTags rt
  JOIN QuestionTags qt ON qt.tag = rt.tag
  JOIN Questions q     ON q.Id   = qt.QuestionId
  LEFT JOIN EditCounts ec ON ec.QuestionId = q.Id
  LEFT JOIN VoteStats vs ON vs.QuestionId   = q.Id
  JOIN Users u ON u.Id = q.OwnerUserId
  JOIN UserAggregates ua ON ua.UserId = u.Id
  JOIN TopBadges tb      ON tb.UserId = u.Id
  WHERE rt.TagRank <= 3
  GROUP BY rt.Month, rt.tag, rt.QuestionsPosted, rt.PrevMonthCount
  ORDER BY rt.Month DESC, Growth DESC
)
SELECT * FROM Final;
