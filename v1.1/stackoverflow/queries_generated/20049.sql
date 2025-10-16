-- {"query": "20049.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1498} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        COUNT(p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalPostScore
    FROM
        Users u
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    WHERE
        u.Reputation > 1000
        AND u.CreationDate < (CURRENT_DATE - INTERVAL '5 year')
        AND p.CommunityOwnedDate IS NULL
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.UserCreationDate
    HAVING
        COUNT(p.Id) > 20
),
AnswerDetails AS (
    SELECT
        a.Id AS AnswerId,
        a.OwnerUserId,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        q.Id AS QuestionId,
        q.Tags AS QuestionTags,
        q.ViewCount AS QuestionViewCount,
        q.CreationDate AS QuestionCreationDate,
        q.AcceptedAnswerId,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) AS SecondsToAnswer,
        LENGTH(a.Body) - LENGTH(REPLACE(a.Body, '<p>', '')) AS ParagraphCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id) AS CommentCountOnAnswer
    FROM
        Posts a
    JOIN
        Posts q ON a.ParentId = q.Id
    WHERE
        a.PostTypeId = 2 -- Answers
        AND q.PostTypeId = 1 -- Questions
        AND q.ClosedDate IS NULL
        AND q.DeletionDate IS NULL
),
RankedUserPerformance AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.GoldBadges,
        ua.SilverBadges,
        ad.AnswerId,
        ad.AnswerScore,
        ad.SecondsToAnswer,
        ad.ParagraphCount,
        ad.CommentCountOnAnswer,
        ad.QuestionTags,
        ad.QuestionViewCount,
        (ad.AnswerId = ad.AcceptedAnswerId) AS IsAcceptedAnswer,
        NTILE(100) OVER (PARTITION BY ua.UserId ORDER BY ad.AnswerScore DESC) AS AnswerScorePercentile,
        AVG(ad.AnswerScore) OVER (PARTITION BY ua.UserId) AS UserAvgAnswerScore,
        LAG(ad.AnswerCreationDate, 1) OVER (PARTITION BY ua.UserId ORDER BY ad.AnswerCreationDate) AS PreviousAnswerDate
    FROM
        UserActivity ua
    JOIN
        AnswerDetails ad ON ua.UserId = ad.OwnerUserId
    WHERE
        ad.SecondsToAnswer BETWEEN 60 AND 86400 * 3 -- Answered between 1 minute and 3 days
),
FinalUserSummary AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        GoldBadges,
        SilverBadges,
        COUNT(AnswerId) AS NumAnswers,
        SUM(CASE WHEN IsAcceptedAnswer THEN 1 ELSE 0 END) AS NumAcceptedAnswers,
        CAST(SUM(CASE WHEN IsAcceptedAnswer THEN 1 ELSE 0 END) AS DECIMAL) / COUNT(AnswerId) AS AcceptanceRate,
        AVG(AnswerScore) AS AvgScore,
        AVG(SecondsToAnswer) / 3600.0 AS AvgHoursToAnswer,
        MAX(ParagraphCount) AS MaxParagraphs,
        SUM(CommentCountOnAnswer) AS TotalCommentsOnAnswers,
        SUM(CASE WHEN AnswerScorePercentile <= 10 THEN 1 ELSE 0 END) AS Top10PercentileAnswers,
        AVG(EXTRACT(EPOCH FROM (AnswerCreationDate - PreviousAnswerDate))) / 86400.0 AS AvgDaysBetweenAnswers
    FROM
        RankedUserPerformance
    GROUP BY
        UserId, DisplayName, Reputation, GoldBadges, SilverBadges
    HAVING
        COUNT(AnswerId) > 10
        AND SUM(CASE WHEN IsAcceptedAnswer THEN 1 ELSE 0 END) > 2
)
SELECT
    fus.DisplayName,
    fus.Reputation,
    fus.NumAnswers,
    fus.AcceptanceRate,
    fus.AvgScore,
    fus.AvgHoursToAnswer,
    fus.AvgDaysBetweenAnswers,
    CASE
        WHEN fus.GoldBadges > 5 AND fus.AcceptanceRate > 0.5 THEN 'Elite Specialist'
        WHEN fus.SilverBadges > 20 AND fus.AvgHoursToAnswer < 12 THEN 'Dedicated Responder'
        WHEN fus.Top10PercentileAnswers > fus.NumAnswers * 0.1 THEN 'High-Impact Contributor'
        ELSE 'Consistent Participant'
    END AS UserTier,
    (SELECT STRING_AGG(DISTINCT t.TagName, ', ')
     FROM Posts p_tags
     JOIN Tags t ON CONCAT('<', t.TagName, '>') LIKE ANY(STRING_TO_ARRAY(p_tags.Tags, ''))
     WHERE p_tags.OwnerUserId = fus.UserId
       AND t.Count > (SELECT AVG(Count) FROM Tags)
    ) AS FrequentHighCountTags,
    (SELECT v.CreationDate
     FROM Votes v
     WHERE v.UserId = fus.UserId AND v.VoteTypeId = 8 -- BountyStart
     ORDER BY v.CreationDate DESC
     LIMIT 1
    ) AS LastBountyStartDate
FROM
    FinalUserSummary fus
LEFT JOIN
    (SELECT DISTINCT UserId FROM PostHistory WHERE PostHistoryTypeId = 10) AS ClosedPostsHistory
    ON fus.UserId = ClosedPostsHistory.UserId
WHERE
    fus.AvgScore > (SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY Score) FROM Posts WHERE PostTypeId = 2)
    AND ClosedPostsHistory.UserId IS NULL -- Exclude users who have voted to close posts
ORDER BY
    (fus.Reputation * 0.2) + (fus.NumAcceptedAnswers * 5) + (fus.AvgScore * 2) - (fus.AvgHoursToAnswer) DESC
LIMIT 50;
