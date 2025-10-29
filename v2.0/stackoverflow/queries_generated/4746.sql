-- {"query": "4746.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1585} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  UserEdits AS (
    SELECT
      rpe.UserId,
      COUNT(DISTINCT rpe.PostId) AS distinct_posts_edited,
      MAX(rpe.CreationDate) AS last_edit_date,
      AVG(
        julianday('now') - julianday(u.CreationDate)
      ) AS days_since_user_creation_at_last_edit
    FROM
      RankedPostEdits AS rpe
      JOIN Users AS u
      ON rpe.UserId = u.Id
    WHERE
      rpe.rn = 1
    GROUP BY
      rpe.UserId
  ),
  QuestionAnswers AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId AS QuestionOwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.Title AS QuestionTitle,
      p.Tags AS QuestionTags,
      COUNT(a.Id) AS AnswerCount,
      SUM(CASE WHEN p.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS IsAcceptedAnswer
    FROM
      Posts AS p
      LEFT JOIN Posts AS a
      ON p.Id = a.ParentId
    WHERE
      p.PostTypeId = 1 -- Questions
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.CreationDate,
      p.Title,
      p.Tags
  ),
  PostScores AS (
    SELECT
      PostId,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
      SUM(CASE WHEN VoteTypeId = 3 THEN -1 ELSE 0 END) AS Downvotes,
      COUNT(CASE WHEN VoteTypeId = 5 THEN 1 ELSE NULL END) AS Favorites
    FROM
      Votes
    WHERE
      VoteTypeId IN (2, 3, 5)
    GROUP BY
      PostId
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.Views AS UserViews,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      COUNT(DISTINCT ph.PostId) AS post_history_entries,
      COUNT(DISTINCT c.PostId) AS comments_made_on_posts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS questions_posted,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answers_posted
    FROM
      Users AS u
      LEFT JOIN PostHistory AS ph
      ON u.Id = ph.UserId
      LEFT JOIN Comments AS c
      ON u.Id = c.UserId
      LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.Views,
      u.UpVotes,
      u.DownVotes
  )
SELECT
  qa.QuestionId,
  qa.QuestionTitle,
  qa.QuestionTags,
  ua.DisplayName AS QuestionOwnerDisplayName,
  ua.Reputation AS QuestionOwnerReputation,
  ua.UserViews AS QuestionOwnerViews,
  qa.AnswerCount,
  COALESCE(ps.Upvotes, 0) AS TotalUpvotes,
  COALESCE(ps.Downvotes, 0) AS TotalDownvotes,
  COALESCE(ps.Favorites, 0) AS TotalFavorites,
  CASE
    WHEN qa.IsAcceptedAnswer > 0 THEN 'Accepted'
    ELSE 'Not Accepted'
  END AS AnswerStatus,
  ue.last_edit_date,
  ue.days_since_user_creation_at_last_edit,
  COALESCE(ue.distinct_posts_edited, 0) AS user_distinct_posts_edited,
  ua.post_history_entries,
  ua.comments_made_on_posts,
  ua.questions_posted,
  ua.answers_posted,
  CASE
    WHEN qa.QuestionTags LIKE '%<sql>%' THEN 'SQL Tag Present'
    ELSE 'SQL Tag Absent'
  END AS HasSqlTag,
  CASE
    WHEN qa.QuestionCreationDate BETWEEN DATE('now', '-7 day') AND DATE('now') THEN 'Last Week'
    WHEN qa.QuestionCreationDate BETWEEN DATE('now', '-30 day') AND DATE('now', '-7 day') THEN '3-4 Weeks Ago'
    ELSE 'Older Than 4 Weeks'
  END AS QuestionAgeGroup,
  LENGTH(qa.QuestionTitle) AS TitleLength,
  UPPER(SUBSTRING(qa.QuestionTitle, 1, 1)) AS FirstTitleChar,
  CASE
    WHEN INSTR(qa.QuestionTags, 'python') > 0
    AND INSTR(qa.QuestionTags, 'django') > 0 THEN 'Python & Django'
    WHEN INSTR(qa.QuestionTags, 'javascript') > 0 THEN 'JavaScript Related'
    ELSE 'Other'
  END AS TagCombination,
  LAG(ua.Reputation, 1, 0) OVER (ORDER BY ua.Reputation DESC) AS PreviousReputation,
  LEAD(ua.Reputation, 1, 0) OVER (ORDER BY ua.Reputation ASC) AS NextReputation,
  ROW_NUMBER() OVER (ORDER BY COALESCE(ps.Upvotes, 0) DESC, qa.AnswerCount DESC) AS RankByScoreAndAnswers
FROM
  QuestionAnswers AS qa
  LEFT JOIN PostScores AS ps
  ON qa.QuestionId = ps.PostId
  LEFT JOIN UserEdits AS ue
  ON qa.QuestionOwnerUserId = ue.UserId
  LEFT JOIN UserActivity AS ua
  ON qa.QuestionOwnerUserId = ua.UserId
WHERE
  ua.Reputation > 1000
  OR ua.UserViews > 5000
UNION
SELECT
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL
FROM
  Users
LIMIT
  1;
