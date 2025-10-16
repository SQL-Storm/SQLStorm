-- {"query": "20086.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1136} 
WITH UserActivitySummary AS (
    SELECT
        OwnerUserId,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(CASE WHEN PostTypeId = 2 THEN Score ELSE 0 END) AS TotalAnswerScore
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
EliteUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.Location, 'N/A') AS Location,
        uas.TotalQuestions,
        uas.TotalAnswers,
        uas.TotalAnswerScore,
        CAST(uas.TotalQuestions AS DECIMAL) / NULLIF(uas.TotalAnswers, 0) AS UserQARatio
    FROM Users u
    JOIN UserActivitySummary uas ON u.Id = uas.OwnerUserId
    WHERE u.Id IN (
        SELECT UserId FROM Badges WHERE Class = 1 GROUP BY UserId HAVING COUNT(*) >= 2
    ) AND uas.TotalQuestions > 5 AND u.Reputation > 10000 AND u.AboutMe IS NOT NULL
),
RankedUserQuestions AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.CreationDate,
        p.FavoriteCount,
        p.Tags,
        p.AcceptedAnswerId,
        LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevQuestionDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS QuestionRank
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IN (SELECT Id FROM EliteUsers)
),
LocationPeerAnalysis AS (
    SELECT
        EXTRACT(YEAR FROM u.CreationDate) AS JoinYear,
        COALESCE(u.Location, 'N/A') AS Location,
        AVG(CAST(uas.TotalQuestions AS DECIMAL) / NULLIF(uas.TotalAnswers, 0)) AS AvgLocationQARatio,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY u.Reputation) AS MedianReputation
    FROM Users u
    JOIN UserActivitySummary uas ON u.Id = uas.OwnerUserId
    WHERE u.Location IS NOT NULL AND u.Location <> ''
    GROUP BY JoinYear, u.Location
    HAVING COUNT(*) > 10
)
SELECT
    eu.DisplayName,
    eu.Reputation,
    ruq.Title AS LastQuestionTitle,
    ruq.Score AS LastQuestionScore,
    ruq.CreationDate AS LastQuestionDate,
    EXTRACT(EPOCH FROM (ruq.CreationDate - ruq.PrevQuestionDate)) / 86400.0 AS DaysSincePrevQuestion,
    eu.UserQARatio,
    lpa.AvgLocationQARatio,
    eu.UserQARatio - lpa.AvgLocationQARatio AS RatioDeltaFromPeer,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ruq.Id) AS CommentCountOnLastQuestion,
    (SELECT STRING_AGG(t.TagName, ', ') FROM UNNEST(string_to_array(substring(ruq.Tags, 2, length(ruq.Tags)-2), '><')) AS tag_name JOIN Tags t ON t.TagName = tag_name WHERE t.IsRequired) AS RequiredTags,
    CASE
        WHEN ans.Body IS NULL THEN 'NO_ACCEPTED_ANSWER'
        WHEN LENGTH(ans.Body) > 4000 THEN 'LONG_ANSWER'
        WHEN LENGTH(ans.Body) > 1000 THEN 'MEDIUM_ANSWER'
        ELSE 'SHORT_ANSWER'
    END AS AcceptedAnswerSize,
    (
        SELECT vt.Name
        FROM Votes v
        JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
        WHERE v.PostId = ruq.Id
        GROUP BY vt.Name
        ORDER BY COUNT(*) DESC
        LIMIT 1
    ) AS MostFrequentVoteType
FROM EliteUsers eu
JOIN RankedUserQuestions ruq ON eu.Id = ruq.OwnerUserId
LEFT JOIN LocationPeerAnalysis lpa ON eu.Location = lpa.Location AND EXTRACT(YEAR FROM eu.CreationDate) = lpa.JoinYear
LEFT JOIN Posts ans ON ruq.AcceptedAnswerId = ans.Id
WHERE ruq.QuestionRank = 1
  AND eu.UserQARatio > lpa.AvgLocationQARatio
  AND ruq.FavoriteCount > (SELECT AVG(FavoriteCount) FROM Posts WHERE PostTypeId = 1 AND CreationDate > eu.CreationDate)
ORDER BY RatioDeltaFromPeer DESC NULLS LAST, eu.Reputation DESC
LIMIT 200;