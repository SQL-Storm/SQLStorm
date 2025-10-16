-- {"query": "1033.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1647} 
WITH RankedAnswers AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        ROW_NUMBER() OVER(PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate) AS AnswerRank,
        COUNT(*) OVER(PARTITION BY a.ParentId) AS TotalAnswers,
        COALESCE(u.Reputation, 0) AS AuthorReputation,
        COALESCE(u.DisplayName, 'Anonymous') AS AuthorName,
        -- Length normalized score calculation with sqrt and log to simulate heavier computation
        POWER(ABS(a.Score) + 1, 0.75) * LOG(GREATEST(LENGTH(COALESCE(a.Body, '')), 1) + 1) AS WeightedScore
    FROM
        Posts a
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE
        a.PostTypeId = 2 -- Answers
), QuestionDetails AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Tags,
        q.CreationDate AS QuestionCreation,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        COALESCE(u.DisplayName, 'Anonymous') AS QuestionOwner,
        COALESCE(u.Reputation, 0) AS QuestionOwnerReputation
    FROM
        Posts q
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    WHERE
        q.PostTypeId = 1 -- Questions
        AND q.ClosedDate IS NULL -- Only open questions
), LatestComments AS (
    SELECT
        c.PostId,
        MAX(c.CreationDate) AS LastCommentDate
    FROM
        Comments c
    GROUP BY
        c.PostId
), DuplicateLinks AS (
    SELECT DISTINCT
        pl.PostId,
        pl.RelatedPostId
    FROM
        PostLinks pl
    INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE
        lt.Name = 'Duplicate'
), UserBadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class=1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class=2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class=3) AS BronzeBadges
    FROM
        Badges b
    GROUP BY
        b.UserId
), QuestionAnswerStats AS (
    SELECT
        q.QuestionId,
        COUNT(a.AnswerId) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.WeightedScore) AS MaxWeightedAnswerScore,
        MAX(a.AuthorReputation) AS MaxAnswerAuthorReputation,
        SUM(CASE WHEN a.AnswerRank = 1 THEN 1 ELSE 0 END) AS HasTopAnswer
    FROM
        QuestionDetails q
    LEFT JOIN RankedAnswers a ON q.QuestionId = a.QuestionId
    GROUP BY
        q.QuestionId
), RecentPostHistoryEdits AS (
    SELECT
        ph.PostId,
        COUNT(*) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM
        PostHistory ph
    WHERE
        ph.PostHistoryTypeId IN (4,5,6) -- Edit Title, Body, Tags
        AND ph.CreationDate > NOW() - INTERVAL '30 days'
    GROUP BY
        ph.PostId
), UserActivityWindows AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id ORDER BY v.CreationDate RANGE BETWEEN INTERVAL '30 days' PRECEDING AND CURRENT ROW) AS VotesLast30Days,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1 AND p.CreationDate > NOW() - INTERVAL '30 days') OVER (PARTITION BY u.Id) AS QuestionsLast30Days,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2 AND p.CreationDate > NOW() - INTERVAL '30 days') OVER (PARTITION BY u.Id) AS AnswersLast30Days
    FROM
        Users u
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
), QuestionWithMetadata AS (
    SELECT
        q.*,
        qa.AvgAnswerScore,
        qa.MaxWeightedAnswerScore,
        qa.MaxAnswerAuthorReputation,
        qa.HasTopAnswer,
        COALESCE(ph.EditCount, 0) AS RecentEditsCount,
        COALESCE(ph.LastEditDate, q.QuestionCreation) AS LastEditOrCreation,
        COALESCE(dl.RelatedPostId, NULL) AS DuplicateOfQuestionId,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges
    FROM
        QuestionDetails q
    LEFT JOIN QuestionAnswerStats qa ON q.QuestionId = qa.QuestionId
    LEFT JOIN RecentPostHistoryEdits ph ON q.QuestionId = ph.PostId
    LEFT JOIN DuplicateLinks dl ON q.QuestionId = dl.PostId
    LEFT JOIN UserBadgeCounts ub ON ub.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = q.QuestionId)
)
SELECT DISTINCT
    qwm.QuestionId,
    qwm.Title,
    qwm.Tags,
    qwm.QuestionCreation,
    qwm.QuestionScore,
    qwm.ViewCount,
    qwm.AnswerCount,
    qwm.FavoriteCount,
    qwm.QuestionOwner,
    qwm.QuestionOwnerReputation,
    qwm.AvgAnswerScore,
    qwm.MaxWeightedAnswerScore,
    qwm.MaxAnswerAuthorReputation,
    qwm.HasTopAnswer,
    qwm.RecentEditsCount,
    qwm.LastEditOrCreation,
    qwm.DuplicateOfQuestionId,
    qwm.GoldBadges,
    qwm.SilverBadges,
    qwm.BronzeBadges,
    la.AnswerId AS TopAnswerId,
    la.Score AS TopAnswerScore,
    la.AuthorName AS TopAnswerAuthor,
    la.AuthorReputation AS TopAnswerReputation,
    STRING_AGG(DISTINCT c.Text, ' | ' ORDER BY c.CreationDate DESC) FILTER (WHERE c.PostId = qwm.QuestionId) AS RecentComments,
    CASE 
        WHEN uact.VotesLast30Days > 100 THEN 'Highly Active Voter'
        WHEN uact.VotesLast30Days BETWEEN 10 AND 100 THEN 'Moderately Active Voter'
        ELSE 'Low Activity Voter'
    END AS VoterActivityLevel
FROM
    QuestionWithMetadata qwm
LEFT JOIN RankedAnswers la ON la.QuestionId = qwm.QuestionId AND la.AnswerRank = 1
LEFT JOIN Comments c ON c.PostId = qwm.QuestionId AND c.CreationDate > NOW() - INTERVAL '60 days'
LEFT JOIN Users u ON u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = qwm.QuestionId)
LEFT JOIN UserActivityWindows uact ON uact.UserId = u.Id
WHERE
    qwm.AnswerCount >= 5
    AND qwm.QuestionScore > 0
    AND (qwm.GoldBadges + qwm.SilverBadges + qwm.BronzeBadges) >= 3
    AND (qwm.DuplicateOfQuestionId IS NULL OR qwm.DuplicateOfQuestionId <> qwm.QuestionId)
ORDER BY
    qwm.QuestionScore DESC,
    qwm.AnswerCount DESC,
    qwm.LastEditOrCreation DESC
LIMIT 50;