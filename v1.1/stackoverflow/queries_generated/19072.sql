-- {"query": "19072.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2637} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate AS UserLastAccessDate,
        u.Views AS UserProfileViews,
        COALESCE(u.UpVotes, 0) AS TotalUpVotesGiven,
        COALESCE(u.DownVotes, 0) AS TotalDownVotesGiven,
        COUNT(DISTINCT p.Id) AS TotalPostsByOwner,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsByOwner,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersByOwner,
        COALESCE(SUM(p.Score), 0) AS TotalPostScoreByOwner,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgPostScoreByOwner,
        MAX(p.CreationDate) AS LatestPostCreationDate,
        COUNT(DISTINCT b.Id) AS TotalBadgesCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgesCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgesCount,
        MIN(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.CreationDate ELSE NULL END) AS FirstAcceptedAnswerDate
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
PostHistoricalMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        SUM(CASE WHEN ph_edit.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditEvents,
        SUM(CASE WHEN ph_close.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalClosureEvents,
        SUM(CASE WHEN ph_reopen.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TotalReopenEvents,
        COALESCE(AVG(c.Score), 0.0) AS AvgCommentScore,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBountyAmount,
        MAX(v.CreationDate) FILTER (WHERE v.VoteTypeId = 2) AS LatestUpVoteDate,
        NTILE(4) OVER (ORDER BY p.ViewCount DESC) AS ViewCountQuartile,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate ASC) AS RankByOwnerScore
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    LEFT JOIN PostHistory AS ph_edit ON p.Id = ph_edit.PostId AND ph_edit.PostHistoryTypeId IN (4, 5, 6, 8) -- Edit/Rollback Title/Body/Tags
    LEFT JOIN PostHistory AS ph_close ON p.Id = ph_close.PostId AND ph_close.PostHistoryTypeId = 10 -- Post Closed
    LEFT JOIN PostHistory AS ph_reopen ON p.Id = ph_reopen.PostId AND ph_reopen.PostHistoryTypeId = 11 -- Post Reopened
    LEFT JOIN Votes AS v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3, 8, 9) -- UpMod, DownMod, BountyStart, BountyClose
    GROUP BY
        p.Id, p.PostTypeId, pt.Name, p.OwnerUserId, p.AcceptedAnswerId, p.ParentId, p.CreationDate, p.LastActivityDate,
        p.Title, p.Tags, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate
),
ProcessedTags AS (
    SELECT
        phm.PostId,
        phm.OwnerUserId,
        TRIM(UNNEST(string_to_array(substring(phm.Tags, 2, length(phm.Tags) - 2), '><'))) AS TagName
    FROM PostHistoricalMetrics AS phm
    WHERE phm.Tags IS NOT NULL AND LENGTH(phm.Tags) > 2
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.TotalQuestionsByOwner,
    uas.TotalAnswersByOwner,
    uas.TotalPostScoreByOwner,
    uas.AvgPostScoreByOwner,
    phm.PostId,
    phm.PostTypeName,
    phm.Title,
    phm.Score AS PostCurrentScore,
    phm.ViewCount,
    phm.AnswerCount,
    phm.CommentCount,
    phm.FavoriteCount,
    phm.AvgCommentScore,
    phm.TotalEditEvents,
    phm.TotalClosureEvents,
    phm.TotalReopenEvents,
    phm.TotalBountyAmount,
    phm.ViewCountQuartile,
    phm.RankByOwnerScore,
    COALESCE(q_acc_post.Score, 0) AS AcceptedAnswerScore,
    COALESCE(q_acc_post.ViewCount, 0) AS AcceptedAnswerViewCount,
    (phm.Score * 0.5 + phm.ViewCount * 0.1 + phm.CommentCount * 0.2 + phm.FavoriteCount * 0.8) AS WeightedEngagementScore,
    (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - phm.LastActivityDate)) / 3600.0) AS HoursSinceLastActivity,
    STRING_AGG(pt.TagName, ', ') FILTER (WHERE pt.TagName IS NOT NULL) AS PostTagList,
    CASE
        WHEN phm.PostTypeId = 1 AND phm.AnswerCount IS NOT NULL AND phm.AnswerCount > 0 AND phm.AcceptedAnswerId IS NULL THEN 'Unanswered with Answers'
        WHEN phm.PostTypeId = 1 AND phm.AnswerCount IS NULL AND phm.ViewCount > 100 THEN 'HighView NoAnswers'
        WHEN phm.ClosedDate IS NOT NULL AND phm.TotalReopenEvents = 0 THEN 'Permanently Closed'
        ELSE 'Active/Resolved'
    END AS PostStatusCategory,
    phm.CreationDate - uas.UserCreationDate AS PostAgeRelativeToUserCreation,
    (
        SELECT COUNT(DISTINCT b_corr.Id)
        FROM Badges AS b_corr
        WHERE b_corr.UserId = uas.UserId
          AND b_corr.Class = 1 -- Gold Badges
          AND (b_corr.Date > uas.FirstAcceptedAnswerDate OR uas.FirstAcceptedAnswerDate IS NULL)
          AND b_corr.Date < phm.CreationDate
    ) AS GoldBadgesBeforePostCreation,
    LEAD(phm.Score, 1, 0) OVER (PARTITION BY uas.UserId ORDER BY phm.PostCreationDate) - phm.Score AS ScoreDifferenceToNextPost,
    NULLIF(phm.TotalEditEvents, 0) AS EditsIfAny
FROM UserActivitySummary AS uas
JOIN PostHistoricalMetrics AS phm ON uas.UserId = phm.OwnerUserId
LEFT JOIN Posts AS q_acc_post ON phm.AcceptedAnswerId = q_acc_post.Id
LEFT JOIN ProcessedTags AS pt ON phm.PostId = pt.PostId
WHERE
    uas.Reputation >= 5000
    AND phm.PostTypeId IN (1, 2) -- Focus on Questions and Answers
    AND phm.Score >= 10
    AND phm.ViewCount >= 500
    AND (phm.FavoriteCount IS NULL OR phm.FavoriteCount >= 5)
    AND phm.PostCreationDate BETWEEN '2019-01-01' AND '2023-12-31'
    AND (phm.ClosedDate IS NULL OR phm.TotalReopenEvents > 0)
    AND EXISTS (
        SELECT 1
        FROM PostHistory AS ph_check
        WHERE ph_check.PostId = phm.PostId
          AND ph_check.PostHistoryTypeId IN (5, 8) -- Body edit or rollback
          AND ph_check.CreationDate BETWEEN phm.CreationDate AND phm.LastActivityDate
          AND ph_check.Comment IS NOT NULL
          AND LENGTH(TRIM(ph_check.Comment)) > 10
          AND ph_check.UserId IS NOT NULL
    )
    AND NOT (phm.Title LIKE '%[Deprecated]%' OR phm.Title ILIKE '%old version%')
    AND phm.LastActivityDate >= (CURRENT_TIMESTAMP - INTERVAL '1 year')
GROUP BY
    uas.UserId, uas.DisplayName, uas.Reputation, uas.TotalQuestionsByOwner, uas.TotalAnswersByOwner,
    uas.TotalPostScoreByOwner, uas.AvgPostScoreByOwner, uas.UserCreationDate, uas.FirstAcceptedAnswerDate,
    phm.PostId, phm.PostTypeName, phm.Title, phm.Score, phm.ViewCount, phm.AnswerCount, phm.CommentCount,
    phm.FavoriteCount, phm.AvgCommentScore, phm.TotalEditEvents, phm.TotalClosureEvents, phm.TotalReopenEvents,
    phm.TotalBountyAmount, phm.ViewCountQuartile, phm.RankByOwnerScore, phm.PostTypeId, phm.AcceptedAnswerId,
    q_acc_post.Score, q_acc_post.ViewCount, phm.LastActivityDate, phm.ClosedDate, phm.CreationDate
HAVING
    COUNT(DISTINCT pt.TagName) > 2 -- Posts must have at least 3 distinct tags
    AND SUM(CASE WHEN pt.TagName IN ('sql-server', 'postgresql', 'mysql', 'database', 'nosql', 'mongodb') THEN 1 ELSE 0 END) >= 1 -- At least one database-related tag
    AND (phm.PostTypeId = 1 OR (phm.PostTypeId = 2 AND phm.Score > phm.AvgCommentScore * 2)) -- Answers with significantly higher score than avg comments, or any question
ORDER BY
    uas.Reputation DESC,
    WeightedEngagementScore DESC,
    phm.CreationDate ASC
LIMIT 5000;
