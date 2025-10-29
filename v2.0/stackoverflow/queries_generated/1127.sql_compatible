WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalPostViews,
        COALESCE(SUM(p.FavoriteCount), 0) AS TotalPostFavorites,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id
),
UserReputationRank AS (
    SELECT
        Id AS UserId,
        Reputation,
        UpVotes,
        DownVotes,
        (UpVotes - DownVotes) AS NetVotes,
        RANK() OVER (ORDER BY Reputation DESC) AS ReputationRank,
        NTILE(5) OVER (ORDER BY Reputation DESC) AS ReputationQuintile
    FROM Users
),
UserRecentGoldBadge AS (
    SELECT
        b.UserId,
        b.Name AS RecentGoldBadgeName,
        b.Date AS RecentGoldBadgeDate,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn
    FROM Badges b
    WHERE b.Class = 1
),
TagPerformanceMetrics AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS DatabaseRelatedQuestionCount,
        COALESCE(SUM(p.Score), 0) AS DatabaseRelatedQuestionScore,
        COALESCE(AVG(p.ViewCount), 0) AS AvgDatabaseRelatedQuestionViews,
        COALESCE(SUM(p.AnswerCount), 0) AS TotalDatabaseRelatedAnswersReceived
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
      AND (p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<database>%')
    GROUP BY p.OwnerUserId
),
ProblematicPosts AS (
    SELECT p.Id AS PostId, p.OwnerUserId AS ProblematicPostOwnerId, p.Title, 'Closed and Reopened' AS ProblemType, ph_close.CreationDate AS ClosureDate
    FROM Posts p
    JOIN PostHistory ph_close ON p.Id = ph_close.PostId
    JOIN PostHistory ph_reopen ON p.Id = ph_reopen.PostId
    WHERE p.PostTypeId = 1
      AND ph_close.PostHistoryTypeId = 10
      AND ph_reopen.PostHistoryTypeId = 11
      AND ph_reopen.CreationDate > ph_close.CreationDate

    UNION ALL

    SELECT p.Id AS PostId, p.OwnerUserId AS ProblematicPostOwnerId, p.Title, 'Closed Specific Reason' AS ProblemType, ph.CreationDate AS ClosureDate
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN CloseReasonTypes crt ON ph.Comment = CAST(crt.Id AS VARCHAR) 
    WHERE p.PostTypeId = 1
      AND ph.PostHistoryTypeId = 10
      AND (crt.Name = 'Off-topic' OR crt.Name = 'Needs details or clarity')
      AND NOT EXISTS (SELECT 1 FROM PostHistory ph2 WHERE ph2.PostId = p.Id AND ph2.PostHistoryTypeId = 11 AND ph2.CreationDate > ph.CreationDate)
),
UsersWithQuestionsNoAnswers AS (
    SELECT p.OwnerUserId AS UserId
    FROM Posts p
    WHERE p.PostTypeId = 1
    EXCEPT
    SELECT p.OwnerUserId AS UserId
    FROM Posts p
    WHERE p.PostTypeId = 2
),
PostEditHistoryLag AS (
    SELECT
        ph.PostId,
        ph.UserId AS EditorUserId,
        ph.CreationDate AS CurrentEditDate,
        LAG(ph.CreationDate, 1, TIMESTAMP '1970-01-01 00:00:00') OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousEditDate,
        ph.PostHistoryTypeId,
        pht.Name AS HistoryTypeName,
        EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate, 1, TIMESTAMP '1970-01-01 00:00:00') OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) / 3600 AS HoursSincePreviousEdit
    FROM PostHistory ph
    INNER JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
)
SELECT
    u.Id AS UserID,
    u.DisplayName AS UserName,
    COALESCE(u.Location, 'Unknown Location') AS UserLocation,
    u.CreationDate AS UserAccountCreationDate,
    AGE(TIMESTAMP '2024-10-01 12:34:56', u.CreationDate) AS UserAccountAge,
    u.Reputation,
    urr.ReputationRank,
    urr.ReputationQuintile,
    uas.TotalPosts,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.TotalPostScore,
    uas.TotalCommentsMade,
    uas.TotalCommentScore,
    (SELECT t.TagName FROM Tags t WHERE t.TagName = SUBSTRING(u.DisplayName FROM 1 FOR 5) LIMIT 1) AS DisplayNamePrefixedTag,
    (
        SELECT COUNT(DISTINCT b.Name)
        FROM Badges b
        WHERE b.UserId = u.Id AND b.Class = 1
          AND b.Date >= u.LastAccessDate - INTERVAL '1 year'
    ) AS GoldBadgesLastYear,
    urgb.RecentGoldBadgeName,
    urgb.RecentGoldBadgeDate,
    CASE WHEN uwqna.UserId IS NOT NULL THEN TRUE ELSE FALSE END AS OnlyAsksQuestions,
    tpm.DatabaseRelatedQuestionCount,
    tpm.DatabaseRelatedQuestionScore,
    tpm.AvgDatabaseRelatedQuestionViews,
    tpm.TotalDatabaseRelatedAnswersReceived,
    COUNT(DISTINCT pp.PostId) AS OwnedProblematicPostCount,
    COALESCE(SUM(CASE WHEN pehl.HoursSincePreviousEdit <= 0.08333 THEN 1 ELSE 0 END), 0) AS FastEditCount,
    CASE
        WHEN u.Reputation >= 10000 AND uas.QuestionCount >= 50 AND COALESCE(tpm.DatabaseRelatedQuestionCount,0) >= 10 THEN 'Elite DB Questioner'
        WHEN u.Reputation >= 5000 AND uas.AnswerCount >= 100 AND uas.TotalPostScore >= 2000 THEN 'High Value Answerer'
        WHEN u.Reputation < 1000 AND uwqna.UserId IS NOT NULL AND uas.TotalCommentsMade > 200 THEN 'Comment-Focused Newbie'
        WHEN u.Location IS NULL THEN 'Locationless Wanderer'
        ELSE 'General Contributor'
    END AS DetailedUserCategory,
    COALESCE(UPPER(SUBSTRING(u.AboutMe FROM POSITION('stack' IN LOWER(COALESCE(u.AboutMe, '')) ) FOR 10)), 'No Stack Reference') AS AboutMeStackSnippet,
    (
        SELECT AVG(p_ans.Score)
        FROM Posts p_ans
        JOIN Posts p_q ON p_ans.ParentId = p_q.Id
        WHERE p_ans.OwnerUserId = u.Id
          AND p_q.AcceptedAnswerId = p_ans.Id
          AND p_q.OwnerUserId <> u.Id
          AND p_ans.CreationDate BETWEEN u.CreationDate AND u.LastAccessDate
    ) AS AvgScoreOfAcceptedAnswersGiven,
    (
        SELECT AVG(EXTRACT(DAY FROM (p_ans.CreationDate - p_q.CreationDate)))
        FROM Posts p_q
        JOIN Posts p_ans ON p_q.Id = p_ans.ParentId
        WHERE p_q.OwnerUserId = u.Id
          AND p_ans.OwnerUserId = u.Id
          AND p_q.PostTypeId = 1
          AND p_ans.PostTypeId = 2
          AND p_ans.CreationDate = (SELECT MIN(pa.CreationDate) FROM Posts pa WHERE pa.ParentId = p_q.Id AND pa.OwnerUserId = u.Id)
    ) AS AvgDaysToSelfAnswer
FROM Users u
LEFT JOIN UserActivitySummary uas ON u.Id = uas.UserId
LEFT JOIN UserReputationRank urr ON u.Id = urr.UserId
LEFT JOIN UserRecentGoldBadge urgb ON u.Id = urgb.UserId AND urgb.rn = 1
LEFT JOIN TagPerformanceMetrics tpm ON u.Id = tpm.UserId
LEFT JOIN UsersWithQuestionsNoAnswers uwqna ON u.Id = uwqna.UserId
LEFT JOIN ProblematicPosts pp ON u.Id = pp.ProblematicPostOwnerId
LEFT JOIN PostEditHistoryLag pehl ON u.Id = pehl.EditorUserId
WHERE u.Views > 0
  AND u.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '10 year')
  AND u.LastAccessDate IS NOT NULL
GROUP BY
    u.Id, u.DisplayName, u.Location, u.CreationDate, u.Reputation, urr.ReputationRank, urr.ReputationQuintile,
    uas.TotalPosts, uas.QuestionCount, uas.AnswerCount, uas.TotalPostScore, uas.TotalCommentsMade, uas.TotalCommentScore,
    urgb.RecentGoldBadgeName, urgb.RecentGoldBadgeDate, uwqna.UserId, tpm.DatabaseRelatedQuestionCount,
    tpm.DatabaseRelatedQuestionScore, tpm.AvgDatabaseRelatedQuestionViews, tpm.TotalDatabaseRelatedAnswersReceived,
    u.AboutMe, u.LastAccessDate
HAVING
    COUNT(DISTINCT pp.PostId) > 0 OR COALESCE(uas.TotalPosts,0) > 10 OR COALESCE(tpm.DatabaseRelatedQuestionCount,0) > 0
ORDER BY
    urr.ReputationRank ASC, UserID DESC
LIMIT 5000;