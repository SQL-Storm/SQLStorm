-- {"query": "20042.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1078} 

WITH HighActivityTags AS (
    SELECT
        tag,
        SUM(ViewCount) AS TotalViews,
        COUNT(*) AS QuestionCount
    FROM
        Posts,
        unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS tag
    WHERE
        PostTypeId = 1 AND Tags IS NOT NULL AND ViewCount IS NOT NULL
    GROUP BY
        tag
    HAVING
        COUNT(*) > 100 AND SUM(ViewCount) > 1000000
    ORDER BY
        SUM(ViewCount) DESC
    LIMIT 20
),
UserAnswerStats AS (
    SELECT
        a.OwnerUserId,
        hat.tag,
        COUNT(a.Id) AS AnswersInTag,
        AVG(a.Score) AS AvgScoreInTag,
        SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswersInTag,
        (
            SELECT SUM(v.BountyAmount)
            FROM Votes v
            WHERE v.PostId = q.Id AND v.VoteTypeId = 8 -- BountyStart
        ) AS TotalBountyOnQuestions
    FROM
        Posts a
    JOIN
        Posts q ON a.ParentId = q.Id
    JOIN
        HighActivityTags hat ON q.Tags LIKE '%' || hat.tag || '%'
    WHERE
        a.PostTypeId = 2 AND a.OwnerUserId IS NOT NULL
    GROUP BY
        a.OwnerUserId, hat.tag
),
RankedUsers AS (
    SELECT
        Id,
        DisplayName,
        Reputation,
        Age,
        UpVotes,
        DownVotes,
        (UpVotes - DownVotes) AS NetVotes,
        (SELECT MIN(Date) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS FirstGoldBadgeDate,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS TotalComments
    FROM
        Users u
    WHERE
        Reputation > 1000
        AND LastAccessDate > (NOW() - INTERVAL '1 year')
        AND AboutMe IS NOT NULL
),
CombinedData AS (
    SELECT
        ru.Id AS UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.FirstGoldBadgeDate,
        ru.NetVotes,
        ru.TotalComments,
        uas.tag,
        uas.AnswersInTag,
        uas.AvgScoreInTag,
        uas.AcceptedAnswersInTag,
        COALESCE(uas.TotalBountyOnQuestions, 0) AS TotalBountyOnQuestions
    FROM
        RankedUsers ru
    LEFT JOIN
        UserAnswerStats uas ON ru.Id = uas.OwnerUserId
    WHERE
        uas.tag IS NOT NULL
)
SELECT
    DisplayName,
    Reputation,
    tag,
    AnswersInTag,
    CAST(AvgScoreInTag AS DECIMAL(10, 2)) AS AvgScoreInTag,
    AcceptedAnswersInTag,
    TotalBountyOnQuestions,
    DENSE_RANK() OVER (PARTITION BY tag ORDER BY Reputation DESC) AS RepRankInTag,
    Reputation - LAG(Reputation, 1, 0) OVER (PARTITION BY tag ORDER BY Reputation DESC) AS RepGapToPrevious,
    SUM(AnswersInTag) OVER (PARTITION BY DisplayName ORDER BY tag) AS CumulativeAnswersAcrossTags,
    CASE
        WHEN FirstGoldBadgeDate IS NULL THEN 'No Gold Badge'
        WHEN EXTRACT(YEAR FROM FirstGoldBadgeDate) < 2015 THEN 'Veteran Gold'
        ELSE 'Modern Gold'
    END AS BadgeEra,
    (NetVotes * 0.2 + TotalComments * 0.05 + AnswersInTag * 5 + AvgScoreInTag * 2) AS CalculatedEngagementScore,
    (
        SELECT
            string_agg(Name, ', ')
        FROM (
            SELECT
                b.Name
            FROM
                Badges b
            WHERE
                b.UserId = cd.UserId AND b.TagBased = 'f'
            ORDER BY
                b.Date DESC
            LIMIT 3
        ) AS RecentBadges
    ) AS LastThreeNamedBadges
FROM
    CombinedData cd
WHERE
    AnswersInTag > (SELECT AVG(AnswersInTag) FROM UserAnswerStats)
    AND EXISTS (
        SELECT 1
        FROM PostHistory ph
        WHERE ph.UserId = cd.UserId
        AND ph.PostHistoryTypeId IN (10, 11) -- Closed, Reopened
    )
ORDER BY
    tag, RepRankInTag
LIMIT 500;
