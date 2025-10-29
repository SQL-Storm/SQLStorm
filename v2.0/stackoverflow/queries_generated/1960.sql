-- {"query": "1960.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3505} 
WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.AboutMe,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COALESCE(COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1), 0) AS TotalQuestionsAsked,
        COALESCE(COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2), 0) AS TotalAnswersProvided,
        COALESCE(COUNT(DISTINCT c.Id), 0) AS TotalCommentsMade,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalPostViews,
        MAX(GREATEST(u.LastAccessDate, p.LastActivityDate, c.CreationDate)) AS LastOverallActivityDate,
        COUNT(DISTINCT b.Id) AS TotalBadgesEarned,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(CASE WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 100 THEN 1 ELSE 0 END) AS HasDetailedAboutMe
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.AboutMe, u.Views, u.UpVotes, u.DownVotes
),
QuestionEventLifecycle AS (
    SELECT
        q.Id AS PostId,
        q.OwnerUserId,
        q.CreationDate AS QuestionCreationDate,
        q.AcceptedAnswerId,
        q.LastEditDate AS QuestionLastEditDate,
        q.ClosedDate AS QuestionClosedDate,
        q.CommunityOwnedDate,
        q.FavoriteCount,
        COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS TotalEdits,
        COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 10) AS TotalCloseVotes,
        COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 11) AS TotalReopenVotes,
        MIN(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS FirstEditDate,
        MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS LastRelevantEditDate,
        COALESCE(EXTRACT(EPOCH FROM (MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) - MIN(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)))), 0) AS TimeSpanOfEditsSeconds,
        LAG(ph.CreationDate, 1, q.CreationDate) OVER (PARTITION BY q.Id ORDER BY ph.CreationDate) AS PreviousHistoryEventDate,
        EXTRACT(DAY FROM (ph.CreationDate - LAG(ph.CreationDate, 1, q.CreationDate) OVER (PARTITION BY q.Id ORDER BY ph.CreationDate))) AS DaysSincePreviousEvent,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) OVER (PARTITION BY q.Id) AS FirstClosureAttemptDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) OVER (PARTITION BY q.Id) AS FirstReopenAttemptDate,
        -- Correlated subquery example: get the UserId of the first person to close the question
        (
            SELECT UserId
            FROM PostHistory ph_inner
            WHERE ph_inner.PostId = q.Id
              AND ph_inner.PostHistoryTypeId = 10
            ORDER BY ph_inner.CreationDate
            LIMIT 1
        ) AS FirstCloserUserId
    FROM
        Posts q
    LEFT JOIN PostHistory ph ON q.Id = ph.PostId
    WHERE
        q.PostTypeId = 1 -- Only questions
    GROUP BY
        q.Id, q.OwnerUserId, q.CreationDate, q.AcceptedAnswerId, q.LastEditDate, q.ClosedDate, q.CommunityOwnedDate, q.FavoriteCount, ph.Id, ph.CreationDate, ph.PostHistoryTypeId -- Need to include individual history rows for LAG to work
),
QuestionTagUsage AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        TRIM(BOTH '<>' FROM UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(p.Tags, '><', '|'), '<', ''), '|'))) AS TagName
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
HighlyInteractedQuestions AS (
    SELECT
        qel.PostId,
        qel.OwnerUserId,
        qel.QuestionCreationDate,
        qel.QuestionClosedDate,
        qel.TotalEdits,
        qel.TotalCloseVotes,
        qel.TotalReopenVotes,
        COALESCE(qel.TimeSpanOfEditsSeconds, 0) AS TimeSpanOfEditsSeconds,
        (qel.TotalCloseVotes > 0 AND qel.TotalReopenVotes > 0) AS WasClosedAndReopened,
        -- Nested subquery to find average score of answers for this question
        (
            SELECT AVG(a.Score)
            FROM Posts a
            WHERE a.ParentId = qel.PostId AND a.PostTypeId = 2
        ) AS AvgAnswerScore,
        -- Get the number of unique users who commented on this question
        (
            SELECT COUNT(DISTINCT c.UserId)
            FROM Comments c
            WHERE c.PostId = qel.PostId AND c.UserId IS NOT NULL
        ) AS UniqueCommentersOnQuestion,
        COUNT(pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 1) AS TotalLinkedPosts,
        COUNT(pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 3) AS TotalDuplicateSources,
        MAX(qel.DaysSincePreviousEvent) AS MaxDaysBetweenAnyTwoEvents,
        RANK() OVER (PARTITION BY qel.OwnerUserId ORDER BY qel.TotalEdits DESC, qel.TotalCloseVotes DESC) AS EditCloseRankByUser
    FROM
        (SELECT DISTINCT PostId, OwnerUserId, QuestionCreationDate, QuestionClosedDate, TotalEdits, TotalCloseVotes, TotalReopenVotes, TimeSpanOfEditsSeconds FROM QuestionEventLifecycle) qel -- Distinct to avoid duplicate rows from ph join
    LEFT JOIN PostLinks pl ON qel.PostId = pl.PostId
    GROUP BY
        qel.PostId, qel.OwnerUserId, qel.QuestionCreationDate, qel.QuestionClosedDate, qel.TotalEdits, qel.TotalCloseVotes, qel.TotalReopenVotes, qel.TimeSpanOfEditsSeconds
),
AnswerQualityMetrics AS (
    SELECT
        a.Id AS AnswerId,
        a.OwnerUserId,
        a.CreationDate AS AnswerCreationDate,
        a.ParentId AS QuestionId,
        a.Score AS AnswerScore,
        a.ViewCount,
        -- Subquery to check if this answer was accepted
        (
            SELECT EXISTS (SELECT 1 FROM Posts q WHERE q.Id = a.ParentId AND q.AcceptedAnswerId = a.Id)
        ) AS IsAcceptedAnswer,
        COUNT(c.Id) AS CommentsOnAnswerCount,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate) AS RankAmongAnswersForQuestion
    FROM
        Posts a
    LEFT JOIN Comments c ON a.Id = c.PostId
    WHERE
        a.PostTypeId = 2 -- Only answers
    GROUP BY
        a.Id, a.OwnerUserId, a.CreationDate, a.ParentId, a.Score, a.ViewCount
)
-- Main query to analyze "power users" based on their contributions
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.TotalQuestionsAsked AS ContributionCount,
    'QuestionMaster' AS ContributionType,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    COALESCE(SUM(hiq.TotalEdits), 0) AS TotalContributionsEdits,
    COALESCE(SUM(hiq.TotalCloseVotes), 0) AS TotalContributionsClosureEvents,
    COALESCE(SUM(hiq.TotalReopenVotes), 0) AS TotalContributionsReopenEvents,
    COALESCE(AVG(hiq.AvgAnswerScore), 0.0) AS AvgRelatedScore,
    COALESCE(SUM(hiq.UniqueCommentersOnQuestion), 0) AS TotalUniqueCommentersOnContributions,
    STRING_AGG(DISTINCT qtu.TagName, ';') FILTER (WHERE qtu.TagName IS NOT NULL) AS TopContributedTags,
    NTILE(10) OVER (ORDER BY uas.Reputation DESC, COALESCE(SUM(hiq.TotalEdits), 0) DESC) AS ReputationEditDecile,
    -- Correlated subquery for a complex metric: count of posts with high activity AND specific tags
    (
        SELECT COUNT(DISTINCT p_inner.Id)
        FROM Posts p_inner
        JOIN QuestionTagUsage qtu_inner ON p_inner.Id = qtu_inner.PostId
        WHERE p_inner.OwnerUserId = uas.UserId
          AND p_inner.PostTypeId = 1
          AND p_inner.LastEditDate > p_inner.CreationDate
          AND qtu_inner.TagName LIKE '%sql%'
          AND p_inner.Score > (SELECT AVG(p_avg.Score) FROM Posts p_avg WHERE p_avg.PostTypeId = 1)
          AND p_inner.Id IN (SELECT hiq_s.PostId FROM HighlyInteractedQuestions hiq_s WHERE hiq_s.OwnerUserId = uas.UserId AND hiq_s.TotalEdits > 2)
    ) AS SqlRelatedHighActivityQuestions
FROM
    UserActivitySummary uas
LEFT JOIN HighlyInteractedQuestions hiq ON uas.UserId = hiq.OwnerUserId
LEFT JOIN QuestionTagUsage qtu ON hiq.PostId = qtu.PostId
WHERE
    uas.Reputation >= 5000 -- Only highly reputable users
    AND uas.TotalQuestionsAsked >= 10 -- With substantial question activity
    AND uas.HasDetailedAboutMe = 1 -- Who care about their profile
    AND EXISTS (
        SELECT 1
        FROM Badges b_sub
        WHERE b_sub.UserId = uas.UserId
          AND b_sub.Name ILIKE '%suffrage%' -- Example of specific badge name
          AND b_sub.Date > uas.UserCreationDate + INTERVAL '1 year' -- Earned after their first year
    )
GROUP BY
    uas.UserId, uas.DisplayName, uas.Reputation, uas.TotalQuestionsAsked, uas.GoldBadges, uas.SilverBadges, uas.BronzeBadges
HAVING
    COUNT(DISTINCT hiq.PostId) > 5 -- At least 5 "highly interacted" questions
    AND COALESCE(SUM(hiq.TotalEdits), 0) > 10 -- Total edits across questions
    AND COALESCE(SUM(hiq.TotalCloseVotes), 0) > COALESCE(SUM(hiq.TotalReopenVotes), 0) -- More closures than reopens (potential for controversial topics)
UNION ALL
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.TotalAnswersProvided AS ContributionCount,
    'AnswerHero' AS ContributionType,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    COALESCE(SUM(aqm.CommentsOnAnswerCount), 0) AS TotalContributionsComments,
    COALESCE(SUM(CASE WHEN aqm.IsAcceptedAnswer THEN 1 ELSE 0 END), 0) AS TotalAcceptedAnswers,
    COALESCE(SUM(aqm.AnswerScore), 0) AS TotalAnswerScore,
    COALESCE(AVG(aqm.AnswerScore), 0.0) AS AvgAnswerScore,
    COALESCE(AVG(aqm.ViewCount), 0.0) AS AvgAnswerViews,
    STRING_AGG(DISTINCT qtu_parent.TagName, ';') FILTER (WHERE qtu_parent.TagName IS NOT NULL) AS TopAnsweredTags,
    NTILE(10) OVER (ORDER BY uas.Reputation DESC, COALESCE(SUM(aqm.AnswerScore), 0) DESC) AS ReputationScoreDecile,
    -- Correlated subquery: count answers that are accepted and have high score
    (
        SELECT COUNT(DISTINCT a_inner.Id)
        FROM Posts a_inner
        WHERE a_inner.OwnerUserId = uas.UserId
          AND a_inner.PostTypeId = 2
          AND a_inner.Score >= 10
          AND EXISTS (SELECT 1 FROM Posts q_inner WHERE q_inner.Id = a_inner.ParentId AND q_inner.AcceptedAnswerId = a_inner.Id)
          AND a_inner.CreationDate BETWEEN NOW() - INTERVAL '2 year' AND NOW()
    ) AS RecentHighScoringAcceptedAnswers
FROM
    UserActivitySummary uas
LEFT JOIN AnswerQualityMetrics aqm ON uas.UserId = aqm.OwnerUserId
LEFT JOIN QuestionTagUsage qtu_parent ON aqm.QuestionId = qtu_parent.PostId -- Tags of the questions they answered
WHERE
    uas.Reputation >= 3000 -- Reputable answerers
    AND uas.TotalAnswersProvided >= 20 -- Substantial answer activity
    AND uas.UserUpVotes > uas.UserDownVotes * 3 -- High positive vote ratio
    AND uas.LastOverallActivityDate >= NOW() - INTERVAL '1 year' -- Recently active
GROUP BY
    uas.UserId, uas.DisplayName, uas.Reputation, uas.TotalAnswersProvided, uas.GoldBadges, uas.SilverBadges, uas.BronzeBadges
HAVING
    COALESCE(SUM(CASE WHEN aqm.IsAcceptedAnswer THEN 1 ELSE 0 END), 0) >= 5 -- At least 5 accepted answers
    AND COALESCE(SUM(aqm.AnswerScore), 0) >= 100 -- Total score from answers
ORDER BY
    Reputation DESC, ContributionCount DESC
LIMIT 200;