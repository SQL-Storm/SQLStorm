-- {"query": "50039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 942} 
WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AverageAnswerScore,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(v_up.Id) AS UpvotesGiven
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v_up ON u.Id = v_up.UserId AND v_up.VoteTypeId = 2
    WHERE
        u.Reputation > 10000 AND u.CreationDate < (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '5 year')
    GROUP BY
        u.Id, u.DisplayName, u.Reputation
    HAVING
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) > 50
),
QuestionAnalysis AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.Title,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        (
            SELECT EXTRACT(EPOCH FROM (MIN(a.CreationDate) - q.CreationDate)) / 3600
            FROM Posts a
            WHERE a.ParentId = q.Id
        ) AS HoursToFirstAnswer,
        EXTRACT(EPOCH FROM (aa.CreationDate - q.CreationDate)) / 3600 AS HoursToAcceptedAnswer,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = q.Id AND pl.LinkTypeId = 1) AS TimesLinked,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS TotalEdits
    FROM
        Posts q
    JOIN
        Posts aa ON q.AcceptedAnswerId = aa.Id
    WHERE
        q.PostTypeId = 1
        AND q.ClosedDate IS NULL
        AND q.Score > 25
        AND q.Tags LIKE '%<database>%'
),
RankedQuestionsByUser AS (
    SELECT
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.TotalAnswers,
        uas.AverageAnswerScore,
        uas.GoldBadges,
        uas.UpvotesGiven,
        qa.QuestionId,
        qa.Title AS QuestionTitle,
        qa.QuestionScore,
        qa.ViewCount,
        qa.FavoriteCount,
        qa.HoursToFirstAnswer,
        qa.HoursToAcceptedAnswer,
        qa.TimesLinked,
        qa.TotalEdits,
        ROW_NUMBER() OVER(PARTITION BY uas.UserId ORDER BY qa.QuestionScore DESC, qa.ViewCount DESC) as rn
    FROM
        UserActivitySummary uas
    JOIN
        QuestionAnalysis qa ON uas.UserId = qa.OwnerUserId
)
SELECT
    r.DisplayName,
    r.Reputation,
    r.AverageAnswerScore,
    r.GoldBadges,
    r.UpvotesGiven,
    r.QuestionTitle,
    r.QuestionScore,
    r.ViewCount,
    r.HoursToAcceptedAnswer,
    r.TimesLinked,
    r.TotalEdits,
    (SELECT STRING_AGG(c.Text, ' | ') FROM (SELECT Text FROM Comments WHERE PostId = r.QuestionId ORDER BY Score DESC LIMIT 3) c) AS TopComments
FROM
    RankedQuestionsByUser r
WHERE
    r.rn <= 3
ORDER BY
    r.Reputation DESC,
    r.UserId,
    r.rn;