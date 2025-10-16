-- {"query": "1098.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1513} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        ARRAY[t.TagName] AS TagPath,
        1 AS Level
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        t.Id,
        t.TagName,
        r.TagPath || t.TagName,
        r.Level + 1
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON POSITION(t.TagName IN r.TagName) = 0 AND r.Level < 3
),
UserBadgeScores AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(SUM(COALESCE(vt.ScoreValue,0)), 0) AS TotalVoteScore,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT
            v.PostId,
            CASE v.VoteTypeId
                WHEN 2 THEN 1    -- UpMod
                WHEN 3 THEN -1   -- DownMod
                ELSE 0
            END AS ScoreValue
        FROM Votes v
        WHERE v.VoteTypeId IN (2,3)
    ) vt ON vt.PostId = p.Id
    GROUP BY u.Id, u.DisplayName
),
PostAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Score AS QuestionScore,
        COALESCE(a.AnswerCount,0) AS TotalAnswers,
        COALESCE(a.AvgAnswerScore,0.0) AS AvgAnswerScore,
        COALESCE(a.BestAnswerScore, NULL) AS MaxAnswerScore,
        q.Tags
    FROM Posts q
    LEFT JOIN (
        SELECT
            p.ParentId,
            COUNT(*) AS AnswerCount,
            AVG(p.Score) AS AvgAnswerScore,
            MAX(p.Score) AS BestAnswerScore
        FROM Posts p
        WHERE p.PostTypeId = 2
        GROUP BY p.ParentId
    ) a ON a.ParentId = q.Id
    WHERE q.PostTypeId = 1
),
TopAnswersWithComments AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.Score,
        a.CreationDate,
        COUNT(c.Id) AS CommentCount,
        STRING_AGG(COALESCE(c.Text, ''), ' | ' ORDER BY c.CreationDate DESC) AS AllComments
    FROM Posts a
    LEFT JOIN Comments c ON c.PostId = a.Id
    WHERE a.PostTypeId = 2
    GROUP BY a.Id, a.ParentId, a.Score, a.CreationDate
),
PostHistoryCloseInfo AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS ClosedDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate ELSE NULL END) AS ReopenedDate,
        STRING_AGG(DISTINCT crt.Name, ', ') FILTER (WHERE ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL) AS CloseReasons
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS smallint)
    GROUP BY ph.PostId
)
SELECT
    qas.QuestionId,
    qas.Title,
    qas.CreationDate,
    qas.QuestionScore,
    qas.TotalAnswers,
    qas.AvgAnswerScore,
    qas.MaxAnswerScore,
    CASE WHEN qas.TotalAnswers > 0 THEN
        ROUND(qas.AvgAnswerScore::NUMERIC / NULLIF(qas.QuestionScore,0),4)
    ELSE NULL END AS AnswerToQuestionScoreRatio,
    ub.DisplayName AS QuestionOwner,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ROW_NUMBER() OVER (PARTITION BY ub.UserId ORDER BY qas.CreationDate DESC) AS UserQuestionRank,
    th.CloseReasons,
    th.ClosedDate,
    th.ReopenedDate,
    COALESCE(taa.AnswerId, -1) AS SampleTopAnswerId,
    taa.Score AS TopAnswerScore,
    taa.CommentCount,
    LENGTH(COALESCE(taa.AllComments, '')) AS TotalCommentsLength,
    CASE 
        WHEN POSITION('sql' IN LOWER(qas.Tags)) > 0 THEN 'Contains SQL Tag'
        ELSE 'No SQL Tag'
    END AS TagAnalysis,
    -- Correlated subquery with EXISTS and NULL logic
    EXISTS (
        SELECT 1
        FROM Votes v2
        WHERE v2.PostId = qas.QuestionId
          AND v2.VoteTypeId = 2
          AND v2.CreationDate > qas.CreationDate
    ) AS HasLaterUpvote,
    -- String expression with NULL handling on OwnerDisplayName
    COALESCE(LEFT(NULLIF(qas.Title, ''), 50), '[No Title]') || ' - Owner: ' || COALESCE(NULLIF(ub.DisplayName, ''), 'Anonymous') AS Summary
FROM PostAnswerStats qas
LEFT JOIN Users ub ON ub.Id = (SELECT OwnerUserId FROM Posts WHERE Id = qas.QuestionId)
LEFT JOIN PostHistoryCloseInfo th ON th.PostId = qas.QuestionId
LEFT JOIN (
    SELECT
        QuestionId,
        AnswerId,
        Score,
        CommentCount,
        AllComments,
        ROW_NUMBER() OVER (PARTITION BY QuestionId ORDER BY Score DESC, CreationDate ASC) AS rn
    FROM TopAnswersWithComments
) taa ON taa.QuestionId = qas.QuestionId AND taa.rn = 1

WHERE qas.TotalAnswers > 2
  AND qas.QuestionScore >= ALL (
      SELECT AVG(p.Score) FROM Posts p WHERE p.PostTypeId = 1 AND p.CreationDate >= qas.CreationDate - INTERVAL '30 days'
  )
  AND (th.ClosedDate IS NULL OR th.ReopenedDate > th.ClosedDate)
ORDER BY qas.CreationDate DESC
LIMIT 50

UNION ALL

SELECT
    -1 AS QuestionId,
    'Aggregate Badge Summary' AS Title,
    NOW() AS CreationDate,
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
FROM Users u
WHERE u.Reputation > (
    SELECT AVG(Reputation) + STDDEV(Reputation) FROM Users
)
ORDER BY 1 DESC;
