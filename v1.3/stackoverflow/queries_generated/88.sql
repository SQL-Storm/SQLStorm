-- {"query": "88.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1772} 
WITH
-- recent activity per post with complex string/tag parsing and null-safe logic
PostTagExplode AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    COALESCE(NULLIF(p.OwnerUserId, 0), NULL) AS OwnerUserId,
    regexp_split_to_table(
      CASE WHEN p.Tags IS NULL THEN '' ELSE substring(p.Tags, 2, char_length(p.Tags)-2) END,
      '><'
    ) AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions only
),
-- best answer metrics using correlated subquery and window functions
AnswerStats AS (
  SELECT
    a.ParentId AS QuestionId,
    COUNT(*) FILTER (WHERE a.Score > 0) AS PosAnswerCount,
    COUNT(*) FILTER (WHERE a.Score <= 0) AS NonPosAnswerCount,
    MAX(a.Score) AS MaxAnswerScore,
    MIN(a.Score) AS MinAnswerScore,
    AVG(a.Score)::numeric(10,3) AS AvgAnswerScore,
    SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS HasAcceptedMatch,
    COUNT(*) AS TotalAnswers
  FROM Posts a
  LEFT JOIN Posts q ON q.Id = a.ParentId
  WHERE a.PostTypeId = 2
  GROUP BY a.ParentId
),
-- compute user engagement windows and ranks
UserEngagement AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COALESCE(u.Views,0) AS Views,
    COALESCE(u.UpVotes,0) AS UpVotes,
    COALESCE(u.DownVotes,0) AS DownVotes,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAuthored,
    COUNT(DISTINCT p2.Id) FILTER (WHERE p2.PostTypeId = 2) AS AnswersAuthored,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS ReputationRank,
    RANK() OVER (PARTITION BY date_trunc('year', u.CreationDate) ORDER BY u.Reputation DESC) AS YearlyReputationRank
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Posts p2 ON p2.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
-- heavy join: recent comments + post + author + badge aggregates
CommentsWithBadges AS (
  SELECT
    c.Id AS CommentId,
    c.PostId,
    c.Text AS CommentText,
    c.CreationDate AS CommentDate,
    COALESCE(u.DisplayName, c.UserDisplayName, 'anon') AS CommentAuthor,
    u.Id AS CommentAuthorId,
    COALESCE(badges.Gold,0) AS GoldBadges,
    COALESCE(badges.Silver,0) AS SilverBadges,
    COALESCE(badges.Bronze,0) AS BronzeBadges
  FROM Comments c
  LEFT JOIN Users u ON u.Id = c.UserId
  LEFT JOIN (
    SELECT UserId,
      SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS Gold,
      SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS Silver,
      SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS Bronze
    FROM Badges
    GROUP BY UserId
  ) badges ON badges.UserId = u.Id
  WHERE c.CreationDate >= now() - interval '180 days'
),
-- assemble final candidate set combining tags, answers, comments, and owners
Candidates AS (
  SELECT
    q.PostId AS QuestionId,
    q.Title,
    q.Tag,
    q.Tags AS RawTags,
    q.OwnerUserId,
    COALESCE(a.TotalAnswers,0) AS TotalAnswers,
    COALESCE(a.MaxAnswerScore,0) AS MaxAnswerScore,
    COALESCE(a.AvgAnswerScore,0) AS AvgAnswerScore,
    c.CommentCount := COALESCE((
      SELECT COUNT(*) FROM Comments cc WHERE cc.PostId = q.PostId
    ),0),
    ua.DisplayName AS OwnerName,
    ua.Reputation AS OwnerReputation,
    ua.ReputationRank,
    -- textual complexity heuristic combining lengths, punctuation density and presence of code tags
    (char_length(COALESCE(q.Title,'')) * 0.3
     + COALESCE(char_length(q.Tags),0) * 0.05
     + (SELECT COALESCE(SUM(length(b.Text)),0) FROM PostHistory b WHERE b.PostId = q.PostId AND b.PostHistoryTypeId IN (2,5)) * 0.001
     + (CASE WHEN COALESCE(position('<code>' IN LOWER(COALESCE(p.Body,''))),0) > 0 THEN 5 ELSE 0 END)
    )::numeric(10,3) AS TextComplexityScore,
    row_number() OVER (PARTITION BY q.Tag ORDER BY COALESCE(a.AvgAnswerScore,0) DESC NULLS LAST, ua.Reputation DESC NULLS LAST) AS TagRank
  FROM PostTagExplode q
  LEFT JOIN AnswerStats a ON a.QuestionId = q.PostId
  LEFT JOIN Users ua ON ua.Id = q.OwnerUserId
)
SELECT
  cid.Tag,
  cid.QuestionId,
  cid.Title,
  cid.OwnerName,
  cid.OwnerReputation,
  cid.TotalAnswers,
  cid.MaxAnswerScore,
  cid.AvgAnswerScore,
  cid.CommentCount,
  cid.TextComplexityScore,
  cid.TagRank,
  -- correlated subquery showing top 3 answer ids concatenated with scores (NULL-safe, filtered)
  (SELECT string_agg(format('%s:%s', ans.Id, ans.Score), ';') FROM (
     SELECT a.Id, a.Score
     FROM Posts a
     WHERE a.ParentId = cid.QuestionId AND a.PostTypeId = 2
     ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC
     LIMIT 3
  ) ans) AS Top3Answers,
  -- set operator example: symmetric difference of close events vs reopen events count
  (SELECT COUNT(*) FROM (
     SELECT posthistory.PostId FROM PostHistory posthistory WHERE posthistory.PostId = cid.QuestionId AND posthistory.PostHistoryTypeId = 10
     EXCEPT
     SELECT posthistory2.PostId FROM PostHistory posthistory2 WHERE posthistory2.PostId = cid.QuestionId AND posthistory2.PostHistoryTypeId = 11
     UNION
     SELECT posthistory2.PostId FROM PostHistory posthistory2 WHERE posthistory2.PostId = cid.QuestionId AND posthistory2.PostHistoryTypeId = 11
     EXCEPT
     SELECT posthistory.PostId FROM PostHistory posthistory WHERE posthistory.PostId = cid.QuestionId AND posthistory.PostHistoryTypeId = 10
  ) x) AS CloseReopenSymmetricDiffCount,
  -- string expression mixing tags and title safely
  COALESCE(NULLIF(cid.Tag,''), 'untagged') || ' :: ' || left(COALESCE(cid.Title,'(no title)'), 100) AS TagTitleSnippet
FROM Candidates cid
WHERE
  -- complicated predicate mixing null logic, math, and existence
  (cid.TotalAnswers >= 2 OR cid.TagRank <= 5)
  AND (cid.OwnerReputation IS NULL OR cid.OwnerReputation < 100000)
  AND cid.TextComplexityScore > (
    SELECT COALESCE(AVG(TextComplexityScore),0) FROM Candidates
  ) * 0.6
  AND EXISTS (
    SELECT 1 FROM Posts p2
    WHERE p2.Id = cid.QuestionId
      AND (p2.ClosedDate IS NULL OR p2.ClosedDate > now() - interval '365 days')
      AND (p2.ViewCount IS NULL OR p2.ViewCount > 10)
  )
ORDER BY cid.Tag, cid.TagRank, cid.TextComplexityScore DESC
LIMIT 200;