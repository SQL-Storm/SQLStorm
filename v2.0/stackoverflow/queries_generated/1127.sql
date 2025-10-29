-- {"query": "1127.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3102} 

WITH UserActivitySummary AS (
    -- Summarizes user post and comment activity, handling NULLs for aggregated scores and counts.
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
    -- Ranks users by reputation and categorizes them into quintiles based on their reputation.
    SELECT
        Id AS UserId,
        Reputation,
        UpVotes,
        DownVotes,
        (UpVotes - DownVotes) AS NetVotes,
        RANK() OVER (ORDER BY Reputation DESC) AS ReputationRank,
        NTILE(5) OVER (ORDER BY Reputation DESC) AS ReputationQuintile -- Divides users into 5 reputation groups
    FROM Users
),
UserRecentGoldBadge AS (
    -- Identifies the most recent gold badge for each user using ROW_NUMBER window function.
    SELECT
        b.UserId,
        b.Name AS RecentGoldBadgeName,
        b.Date AS RecentGoldBadgeDate,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn
    FROM Badges b
    WHERE b.Class = 1 -- Gold badges
),
TagPerformanceMetrics AS (
    -- Aggregates performance metrics for questions specifically tagged with 'sql' or 'database'.
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS DatabaseRelatedQuestionCount,
        COALESCE(SUM(p.Score), 0) AS DatabaseRelatedQuestionScore,
        COALESCE(AVG(p.ViewCount), 0) AS AvgDatabaseRelatedQuestionViews,
        COALESCE(SUM(p.AnswerCount), 0) AS TotalDatabaseRelatedAnswersReceived
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions only
      AND p.Tags IS NOT NULL
      AND (p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<database>%')
    GROUP BY p.OwnerUserId
),
ProblematicPosts AS (
    -- Uses UNION ALL to combine two types of 'problematic' questions:
    -- 1. Questions that were initially closed and later reopened.
    -- 2. Questions closed for specific reasons ('Off-topic' or 'Needs details or clarity') and not subsequently reopened.
    SELECT p.Id AS PostId, p.OwnerUserId AS ProblematicPostOwnerId, p.Title, 'Closed and Reopened' AS ProblemType, ph_close.CreationDate AS ClosureDate
    FROM Posts p
    JOIN PostHistory ph_close ON p.Id = ph_close.PostId
    JOIN PostHistory ph_reopen ON p.Id = ph_reopen.PostId
    WHERE p.PostTypeId = 1
      AND ph_close.PostHistoryTypeId = 10 -- Post Closed
      AND ph_reopen.PostHistoryTypeId = 11 -- Post Reopened
      AND ph_reopen.CreationDate > ph_close.CreationDate

    UNION ALL

    SELECT p.Id AS PostId, p.OwnerUserId AS ProblematicPostOwnerId, p.Title, 'Closed Specific Reason' AS ProblemType, ph.CreationDate AS ClosureDate
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN CloseReasonTypes crt ON ph.Comment = crt.Id::VARCHAR -- Assumes Comment field stores CloseReasonId for type 10
    WHERE p.PostTypeId = 1
      AND ph.PostHistoryTypeId = 10
      AND (crt.Name = 'Off-topic' OR crt.Name = 'Needs details or clarity')
      AND NOT EXISTS (SELECT 1 FROM PostHistory ph2 WHERE ph2.PostId = p.Id AND ph2.PostHistoryTypeId = 11 AND ph2.CreationDate > ph.CreationDate) -- Excludes questions that were reopened
),
UsersWithQuestionsNoAnswers AS (
    -- Identifies users who have asked at least one question but have never provided an answer, using the EXCEPT set operator.
    SELECT p.OwnerUserId AS UserId
    FROM Posts p
    WHERE p.PostTypeId = 1
    EXCEPT
    SELECT p.OwnerUserId AS UserId
    FROM Posts p
    WHERE p.PostTypeId = 2
),
PostEditHistoryLag AS (
    -- Analyzes edit history for posts, calculating the time difference between consecutive edits by the same editor.
    -- Uses LAG window function and EXTRACT for time-based calculations.
    SELECT
        ph.PostId,
        ph.UserId AS EditorUserId,
        ph.CreationDate AS CurrentEditDate,
        LAG(ph.CreationDate, 1, '1970-01-01 00:00:00'::timestamp) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousEditDate,
        ph.PostHistoryTypeId,
        pht.Name AS HistoryTypeName,
        EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate, 1, '1970-01-01 00:00:00'::timestamp) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) / 3600 AS HoursSincePreviousEdit
    FROM PostHistory ph
    INNER JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
)
SELECT
    u.Id AS UserID,
    u.DisplayName AS UserName,
    COALESCE(u.Location, 'Unknown Location') AS UserLocation,
    u.CreationDate AS UserAccountCreationDate,
    AGE(CURRENT_TIMESTAMP, u.CreationDate) AS UserAccountAge, -- Calculates age of user account
    u.Reputation,
    urr.ReputationRank,
    urr.ReputationQuintile,
    uas.TotalPosts,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.TotalPostScore,
    uas.TotalCommentsMade,
    uas.TotalCommentScore,
    -- Correlated subquery: Attempts to find a tag whose name matches the first 5 characters of the user's DisplayName.
    (SELECT t.TagName FROM Tags t WHERE t.TagName = SUBSTRING(u.DisplayName, 1, 5) LIMIT 1) AS DisplayNamePrefixedTag,
    -- Correlated subquery: Counts Gold badges awarded to the user in the last year relative to their last access date.
    (
        SELECT COUNT(DISTINCT b.Name)
        FROM Badges b
        WHERE b.UserId = u.Id AND b.Class = 1
        AND b.Date >= u.LastAccessDate - INTERVAL '1 year'
    ) AS GoldBadgesLastYear,
    -- Details of the user's most recent Gold Badge, joined from a CTE.
    urgb.RecentGoldBadgeName,
    urgb.RecentGoldBadgeDate,
    -- NULL Logic: Flags users who only ask questions based on the UsersWithQuestionsNoAnswers CTE.
    CASE WHEN uwqna.UserId IS NOT NULL THEN TRUE ELSE FALSE END AS OnlyAsksQuestions,
    -- Aggregated tag performance metrics for database-related questions by the user.
    tpm.DatabaseRelatedQuestionCount,
    tpm.DatabaseRelatedQuestionScore,
    tpm.AvgDatabaseRelatedQuestionViews,
    tpm.TotalDatabaseRelatedAnswersReceived,
    -- Counts the number of problematic posts owned by the user, joined from ProblematicPosts CTE.
    COUNT(DISTINCT pp.PostId) AS OwnedProblematicPostCount,
    -- Counts posts with extremely fast edits (within 5 minutes) made by the user, joined from PostEditHistoryLag CTE.
    COALESCE(SUM(CASE WHEN pehl.HoursSincePreviousEdit <= 0.08333 THEN 1 ELSE 0 END), 0) AS FastEditCount, -- 5 minutes = 5/60 = 0.08333 hours
    -- Complicated CASE statement to categorize users based on multiple criteria including reputation, post counts, and specific tag performance.
    CASE
        WHEN u.Reputation >= 10000 AND uas.QuestionCount >= 50 AND tpm.DatabaseRelatedQuestionCount >= 10 THEN 'Elite DB Questioner'
        WHEN u.Reputation >= 5000 AND uas.AnswerCount >= 100 AND uas.TotalPostScore >= 2000 THEN 'High Value Answerer'
        WHEN u.Reputation < 1000 AND uwqna.UserId IS NOT NULL AND uas.TotalCommentsMade > 200 THEN 'Comment-Focused Newbie'
        WHEN u.Location IS NULL THEN 'Locationless Wanderer'
        ELSE 'General Contributor'
    END AS DetailedUserCategory,
    -- String Expression: Extracts a snippet from the user's 'AboutMe' text, specifically looking for 'stack', then converts to uppercase. Uses COALESCE for NULL handling.
    COALESCE(UPPER(SUBSTRING(u.AboutMe FROM POSITION('stack' IN LOWER(u.AboutMe)) FOR 10)), 'No Stack Reference') AS AboutMeStackSnippet,
    -- Correlated subquery: Calculates the average score of accepted answers provided by the user to other users' questions within their activity period.
    (
        SELECT AVG(p_ans.Score)
        FROM Posts p_ans
        JOIN Posts p_q ON p_ans.ParentId = p_q.Id
        WHERE p_ans.OwnerUserId = u.Id
          AND p_q.AcceptedAnswerId = p_ans.Id
          AND p_q.OwnerUserId <> u.Id -- Accepted answer to someone else's question
          AND p_ans.CreationDate BETWEEN u.CreationDate AND u.LastAccessDate
    ) AS AvgScoreOfAcceptedAnswersGiven,
    -- Correlated subquery: Calculates the average number of days between a question's creation and its first answer by the same owner.
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
LEFT JOIN UserRecentGoldBadge urgb ON u.Id = urgb.UserId AND urgb.rn = 1 -- Ensures only the single most recent gold badge is joined
LEFT JOIN TagPerformanceMetrics tpm ON u.Id = tpm.UserId
LEFT JOIN UsersWithQuestionsNoAnswers uwqna ON u.Id = uwqna.UserId
LEFT JOIN ProblematicPosts pp ON u.Id = pp.ProblematicPostOwnerId -- Used for counting problematic posts owned by the user
LEFT JOIN PostEditHistoryLag pehl ON u.Id = pehl.EditorUserId -- Used for counting fast edits made by the user
WHERE u.Views > 0 -- Filters out users with no views
  AND u.CreationDate >= CURRENT_DATE - INTERVAL '10 year' -- Focuses on users created in the last 10 years
  AND u.LastAccessDate IS NOT NULL -- Ensures user has accessed the site
GROUP BY
    u.Id, u.DisplayName, u.Location, u.CreationDate, u.Reputation, urr.ReputationRank, urr.ReputationQuintile,
    uas.TotalPosts, uas.QuestionCount, uas.AnswerCount, uas.TotalPostScore, uas.TotalCommentsMade, uas.TotalCommentScore,
    urgb.RecentGoldBadgeName, urgb.RecentGoldBadgeDate, uwqna.UserId, tpm.DatabaseRelatedQuestionCount,
    tpm.DatabaseRelatedQuestionScore, tpm.AvgDatabaseRelatedQuestionViews, tpm.TotalDatabaseRelatedAnswersReceived,
    u.AboutMe, u.LastAccessDate
HAVING
    COUNT(DISTINCT pp.PostId) > 0 OR uas.TotalPosts > 10 OR tpm.DatabaseRelatedQuestionCount > 0 -- Filters for users with some level of activity or problematic posts
ORDER BY
    urr.ReputationRank ASC, UserID DESC
LIMIT 5000;
