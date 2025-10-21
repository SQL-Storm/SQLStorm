-- {"query": "39090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2702} 

WITH
RecentQuestions AS (
    SELECT
        p.Id               AS QuestionId,
        p.OwnerUserId      AS AskerUserId,
        p.CreationDate,
        p.Score
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > CURRENT_DATE - INTERVAL '1 year'
),
AnswerStats AS (
    SELECT
        a.ParentId         AS QuestionId,
        COUNT(*)           AS AnswerCount,
        AVG(a.Score)       AS AvgAnswerScore,
        MAX(a.Score)       AS MaxAnswerScore
    FROM Posts a
    WHERE a.PostTypeId = 2
      AND a.CreationDate > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY a.ParentId
),
UserActivity AS (
    SELECT
        u.Id                                               AS UserId,
        u.DisplayName,
        COUNT(DISTINCT rq.QuestionId)                      AS QuestionsAsked,
        SUM(COALESCE(ans.AnswerCount, 0))                  AS TotalAnswersOnTheirQuestions,
        AVG(ans.AvgAnswerScore)                            AS AvgAnswerScoreOnTheirQuestions,
        COUNT(c.Id)   FILTER (WHERE c.CreationDate > CURRENT_DATE - INTERVAL '1 year')
                                                           AS CommentsMade,
        COUNT(v.Id)   FILTER (WHERE v.VoteTypeId = 2       -- upvotes
                              AND v.CreationDate > CURRENT_DATE - INTERVAL '1 year')
                                                           AS UpVotesMade,
        COUNT(pl.Id)  FILTER (WHERE pl.LinkTypeId = 3)     AS DuplicateLinksFromQuestions
    FROM Users u
    LEFT JOIN RecentQuestions rq
      ON u.Id = rq.AskerUserId
    LEFT JOIN AnswerStats ans
      ON rq.QuestionId = ans.QuestionId
    LEFT JOIN Comments c
      ON c.UserId = u.Id
    LEFT JOIN Votes v
      ON v.UserId = u.Id
    LEFT JOIN PostLinks pl
      ON pl.PostId = rq.QuestionId
    GROUP BY u.Id, u.DisplayName
),
RankedUsers AS (
    SELECT
        ua.*,
        RANK() OVER (
          ORDER BY ua.QuestionsAsked DESC,
                   ua.TotalAnswersOnTheirQuestions DESC,
                   ua.UpVotesMade DESC
        ) AS ActivityRank
    FROM UserActivity ua
)
SELECT
    ru.UserId,
    ru.DisplayName,
    ru.QuestionsAsked,
    ru.TotalAnswersOnTheirQuestions,
    ROUND(ru.AvgAnswerScoreOnTheirQuestions,2)    AS AvgAnswerScoreOnTheirQuestions,
    ru.CommentsMade,
    ru.UpVotesMade,
    ru.DuplicateLinksFromQuestions,
    ru.ActivityRank,
    COUNT(b.Id)                                  AS BadgesEarned,
    STRING_AGG(DISTINCT b.Name, ', ')            AS BadgeNames,
    SUM(b.Class)                                 AS BadgeScoreSum
FROM RankedUsers ru
LEFT JOIN Badges b
  ON b.UserId = ru.UserId
 AND b.Date > CURRENT_DATE - INTERVAL '1 year'
WHERE ru.ActivityRank <= 50
GROUP BY
    ru.UserId,
    ru.DisplayName,
    ru.QuestionsAsked,
    ru.TotalAnswersOnTheirQuestions,
    ru.AvgAnswerScoreOnTheirQuestions,
    ru.CommentsMade,
    ru.UpVotesMade,
    ru.DuplicateLinksFromQuestions,
    ru.ActivityRank
ORDER BY ru.ActivityRank;
