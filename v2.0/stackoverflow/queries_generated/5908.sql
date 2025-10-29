-- {"query": "5908.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1029} 
WITH
-- Sample derived metrics per user with advanced constructs
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COALESCE(u.Location, '') AS Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    COUNT(DISTINCT a.Id) FILTER (WHERE a.PostTypeId = 2) AS AnswerCount,
    SUM(COALESCE(p.Score,0)) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionScore,
    SUM(COALESCE(a.Score,0)) FILTER (WHERE a.PostTypeId = 2) AS TotalAnswerScore,
    MAX(p.LastActivityDate) FILTER (WHERE p.OwnerUserId = u.Id) AS LastActivityQuestion,
    MAX(a.LastActivityDate) FILTER (WHERE a.OwnerUserId = u.Id) AS LastActivityAnswer
  FROM
    Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.Views, u.UpVotes, u.DownVotes
),
-- Correlated subquery: top 3 most upvoted questions per user, with a window function
TopQuestions AS (
  SELECT
    u.Id AS UserId,
    q.Id AS QuestionId,
    q.Title,
    q.Score,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY q.Score DESC, q.CreationDate ASC) AS rn
  FROM
    Users u
    JOIN Posts q ON q.OwnerUserId = u.Id AND q.PostTypeId = 1
  WHERE
    q.Score > 0
),
-- Complex CTEs with JSON-like aggregation using string functions to simulate nested expressions
TaggedActivity AS (
  SELECT
    u.Id AS UserId,
    STRING_AGG(DISTINCT t.TagName, ',') AS TagsInteracted,
    COUNT(*) AS ActivityCount
  FROM
    Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN LATERAL (
      SELECT unnest(string_to_array(p.Tags, '>')) AS TagName
    ) AS t ON TRUE
  WHERE
    p.PostTypeId = 1
  GROUP BY
    u.Id
),
-- Windowed ranking across tags by interaction count
TagRank AS (
  SELECT
    ta.UserId,
    ta.TagsInteracted,
    ta.ActivityCount,
    ROW_NUMBER() OVER (ORDER BY ta.ActivityCount DESC, ta.TagsInteracted) AS rank
  FROM TaggedActivity ta
),
-- Final set joining diverse constructs
FinalResult AS (
  SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.TotalQuestionScore,
    us.TotalAnswerScore,
    COALESCE(tk.rank, 9999) AS TagActivityRank,
    COALESCE(tk.TagsInteracted, '') AS MostActiveTags,
    ARRAY_AGG(DISTINCT TOPQ.QuestionId) FILTER (WHERE TOPQ.rn <= 3) AS TopQuestionIds,
    ARRAY_AGG(DISTINCT TOPQ.Title) FILTER (WHERE TOPQ.rn <= 3) AS TopQuestionTitles,
    EXISTS (
      SELECT 1
      FROM Votes v
      WHERE v.UserId = us.UserId
        AND v.VoteTypeId = 2 -- UpMod
        AND v.CreationDate > NOW() - INTERVAL '1 year'
    ) AS HasUpvotedLastYear
  FROM
    UserStats us
    LEFT JOIN TagRank tk ON tk.UserId = us.UserId
    LEFT JOIN TopQuestions TOPQ ON TOPQ.UserId = us.UserId
  GROUP BY
    us.UserId, us.DisplayName, us.Reputation, us.QuestionCount, us.AnswerCount, us.TotalQuestionScore, us.TotalAnswerScore, tk.rank, tk.TagsInteracted, TOPQ.QuestionId, TOPQ.Title, TOPQ.rn
)
SELECT
  fr.UserId,
  fr.DisplayName,
  fr.Reputation,
  fr.QuestionCount,
  fr.AnswerCount,
  fr.TotalQuestionScore,
  fr.TotalAnswerScore,
  fr.TagActivityRank,
  fr.MostActiveTags,
  fr.TopQuestionIds,
  fr.TopQuestionTitles,
  fr.HasUpvotedLastYear
FROM FinalResult fr
ORDER BY fr.Reputation DESC, fr.TagActivityRank ASC
LIMIT 100;