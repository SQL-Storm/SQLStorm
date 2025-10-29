-- {"query": "1873.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2781} 

WITH UserStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        EXTRACT(EPOCH FROM (NOW() - u.CreationDate)) / (3600 * 24 * 365.25) AS AccountAgeYears,
        CASE
            WHEN u.Reputation >= 100000 THEN 'Legend'
            WHEN u.Reputation >= 25000 THEN 'Guru'
            WHEN u.Reputation >= 5000 THEN 'Expert'
            WHEN u.Reputation >= 1000 THEN 'Advanced'
            WHEN u.Reputation >= 100 THEN 'Active'
            ELSE 'Novice'
        END AS ReputationTier,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersGiven,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavoriteCountsReceived,
        MAX(p.CreationDate) AS LatestPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
PostTagsExpanded AS (
    SELECT
        p.Id AS PostId,
        TRIM(BOTH '<>' FROM tag_val) AS TagName
    FROM Posts p,
    LATERAL UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag_val
    WHERE p.Tags IS NOT NULL AND p.Tags != '' AND p.PostTypeId = 1
),
PostActivityMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Title,
        p.Tags,
        p.ClosedDate,
        (SELECT COUNT(DISTINCT c.UserId) FROM Comments c WHERE c.PostId = p.Id AND c.UserId IS NOT NULL) AS UniqueCommenters,
        (SELECT SUM(s.Score) FROM Comments s WHERE s.PostId = p.Id) AS TotalCommentScore,
        COUNT(DISTINCT ph.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenVoteCount,
        MAX(ph.CreationDate) AS LastHistoryDate,
        STRING_AGG(DISTINCT pte.TagName, ', ') FILTER (WHERE pte.TagName IS NOT NULL) AS AssociatedTags_Aggregated,
        COALESCE(p.FavoriteCount, 0) * 0.5 + p.Score * 1.0 + p.ViewCount * 0.01 + p.CommentCount * 0.75 + COALESCE(p.AnswerCount, 0) * 2.0 AS PostEngagementScore
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN PostTagsExpanded pte ON p.Id = pte.PostId
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.Score, p.ViewCount,
        p.AnswerCount, p.CommentCount, p.FavoriteCount, p.Title, p.Tags, p.ClosedDate
),
DetailedPostHistory AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryCreationDate,
        ph.UserId AS HistoryUserId,
        pht.Name AS HistoryTypeName,
        cr.Name AS CloseReasonName,
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousHistoryDate,
        EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) / 3600 AS HoursSincePreviousEdit,
        CASE
            WHEN ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL AND ph.Comment SIMILAR TO '[0-9]+'
            THEN CAST(ph.Comment AS SMALLINT)
            ELSE NULL
        END AS CloseReasonId
    FROM PostHistory ph
    INNER JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN CloseReasonTypes cr ON
        (ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL AND ph.Comment SIMILAR TO '[0-9]+' AND cr.Id = CAST(ph.Comment AS SMALLINT))
        OR (ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL AND NOT (ph.Comment SIMILAR TO '[0-9]+') AND cr.Name = ph.Comment)
),
RecentCommenters AS (
    SELECT
        c.PostId,
        c.UserId AS CommenterUserId,
        COUNT(c.Id) AS CommentCountByThisUser,
        MAX(c.CreationDate) AS LastCommentDate,
        DENSE_RANK() OVER (PARTITION BY c.PostId ORDER BY COUNT(c.Id) DESC, MAX(c.CreationDate) DESC) AS CommenterRank
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.PostId, c.UserId
    HAVING COUNT(c.Id) >= 2
)
SELECT
    'QuestionAnalysis' AS ReportType,
    us.DisplayName AS OwnerDisplayName,
    us.Reputation,
    us.ReputationTier,
    pam.PostId,
    pam.Title AS PostTitle,
    SUBSTRING(COALESCE(pam.Title, 'Untitled Question'), 1, 50) || '...' AS ShortPostTitle,
    pam.PostEngagementScore,
    pam.Score AS QuestionScore,
    pam.ViewCount AS QuestionViewCount,
    pam.AnswerCount,
    pam.CommentCount AS QuestionCommentCount,
    pam.TotalCommentScore,
    pam.UniqueCommenters,
    pam.EditCount AS QuestionEditCount,
    ph.CloseReasonName,
    ph.HoursSincePreviousEdit AS LastEditHoursSincePrev,
    us.AccountAgeYears,
    COALESCE(rc.CommenterUserId, -1) AS TopCommenterUserId,
    COALESCE(rc.CommentCountByThisUser, 0) AS TopCommenterCount,
    REPLACE(REPLACE(COALESCE(pam.Tags, ''), '<sql>', '{{SQL}}'), '<database>', '{{DB}}') AS ProcessedTags,
    CASE
        WHEN pam.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN pam.PostEngagementScore > 500 AND pam.AnswerCount = 0 THEN 'HighEngagementUnanswered'
        WHEN pam.Score > 100 AND pam.AnswerCount > 0 THEN 'HighScoreAnswered'
        ELSE 'Other'
    END AS QuestionStatusCategory,
    RANK() OVER (PARTITION BY us.ReputationTier ORDER BY pam.PostEngagementScore DESC) AS RankWithinReputationTier
FROM UserStats us
INNER JOIN PostActivityMetrics pam ON us.UserId = pam.OwnerUserId
LEFT JOIN (
    SELECT
        PostId,
        MAX(CloseReasonName) AS CloseReasonName,
        AVG(HoursSincePreviousEdit) AS HoursSincePreviousEdit
    FROM DetailedPostHistory
    WHERE PostHistoryTypeId = 10
    GROUP BY PostId
) ph ON pam.PostId = ph.PostId
LEFT JOIN RecentCommenters rc ON pam.PostId = rc.PostId AND rc.CommenterRank = 1
WHERE pam.PostTypeId = 1
AND pam.PostCreationDate >= (NOW() - INTERVAL '2 year')
AND pam.Score >= 10
AND us.AccountAgeYears > 1.0
AND (ph.CloseReasonName IS NULL OR ph.CloseReasonName NOT LIKE '%Duplicate%')
AND LENGTH(COALESCE(pam.Title, '')) BETWEEN 15 AND 200
AND pam.PostEngagementScore > 75

UNION ALL

SELECT
    'AnswerAnalysis' AS ReportType,
    us.DisplayName AS OwnerDisplayName,
    us.Reputation,
    us.ReputationTier,
    pam.PostId,
    COALESCE(pq.Title, 'N/A') AS PostTitle, -- Parent question's title
    SUBSTRING(COALESCE(pq.Title, 'N/A'), 1, 50) || '...' AS ShortPostTitle,
    pam.PostEngagementScore,
    pam.Score AS AnswerScore,
    pq.ViewCount AS ParentQuestionViewCount,
    NULL AS AnswerCount, -- Not applicable for answers
    pam.CommentCount AS AnswerCommentCount,
    pam.TotalCommentScore,
    pam.UniqueCommenters,
    pam.EditCount AS AnswerEditCount,
    NULL AS CloseReasonName, -- Not applicable for answers
    ph_ans.HoursSincePreviousEdit AS LastEditHoursSincePrev,
    us.AccountAgeYears,
    COALESCE(rc.CommenterUserId, -1) AS TopCommenterUserId,
    COALESCE(rc.CommentCountByThisUser, 0) AS TopCommenterCount,
    REPLACE(REPLACE(COALESCE(pq.Tags, ''), '<java>', '{{JAVA}}'), '<c#>', '{{CSHARP}}') AS ProcessedTags, -- Parent question's tags
    CASE
        WHEN pam.Score >= 50 THEN 'HighlyRatedAnswer'
        WHEN pam.Score > 0 AND pam.EditCount > 0 THEN 'EditedAcceptedAnswer'
        WHEN pq.AcceptedAnswerId = pam.PostId THEN 'AcceptedAnswer'
        ELSE 'OtherAnswer'
    END AS AnswerStatusCategory,
    RANK() OVER (PARTITION BY us.ReputationTier ORDER BY pam.Score DESC, pam.PostEngagementScore DESC) AS RankWithinReputationTier
FROM UserStats us
INNER JOIN PostActivityMetrics pam ON us.UserId = pam.OwnerUserId
INNER JOIN Posts pa ON pam.PostId = pa.Id -- Answer post itself
INNER JOIN Posts pq ON pa.ParentId = pq.Id -- Parent question
LEFT JOIN (
    SELECT
        PostId,
        AVG(HoursSincePreviousEdit) AS HoursSincePreviousEdit
    FROM DetailedPostHistory
    WHERE PostHistoryTypeId IN (5, 8) -- Edit Body, Rollback Body
    GROUP BY PostId
) ph_ans ON pam.PostId = ph_ans.PostId
LEFT JOIN RecentCommenters rc ON pam.PostId = rc.PostId AND rc.CommenterRank = 1
WHERE pam.PostTypeId = 2
AND pam.PostCreationDate >= (NOW() - INTERVAL '1 year')
AND pam.Score >= 1
AND us.ReputationTier IN ('Guru', 'Expert', 'Advanced')
ORDER BY Reputation DESC, PostEngagementScore DESC
LIMIT 500;
