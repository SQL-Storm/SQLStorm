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
        MAX(CASE WHEN v.VoteTypeId = 2 THEN v.CreationDate ELSE NULL END) AS LatestUpVoteDate,
        NTILE(4) OVER (ORDER BY p.ViewCount DESC) AS ViewCountQuartile,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate ASC) AS RankByOwnerScore
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    LEFT JOIN PostHistory AS ph_edit ON p.Id = ph_edit.PostId AND ph_edit.PostHistoryTypeId IN (4, 5, 6, 8)
    LEFT JOIN PostHistory AS ph_close ON p.Id = ph_close.PostId AND ph_close.PostHistoryTypeId = 10
    LEFT JOIN PostHistory AS ph_reopen ON p.Id = ph_reopen.PostId AND ph_reopen.PostHistoryTypeId = 11
    LEFT JOIN Votes AS v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3, 8, 9)
    GROUP BY
        p.Id, p.PostTypeId, pt.Name, p.OwnerUserId, p.AcceptedAnswerId, p.ParentId, p.CreationDate, p.LastActivityDate,
        p.Title, p.Tags, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate
),
ProcessedTags AS (
    SELECT
        phm.PostId,
        phm.OwnerUserId,
        TRIM(UNNEST(string_to_array(SUBSTRING(phm.Tags FROM 2 FOR (LENGTH(phm.Tags) - 2)), '><'))) AS TagName
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
    (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - phm.LastActivityDate)) / 3600.0) AS HoursSinceLastActivity,
    STRING_AGG(pt.TagName, ', ') FILTER (WHERE pt.TagName IS NOT NULL) AS PostTagList,
    CASE
        WHEN phm.PostTypeId = 1 AND phm.AnswerCount IS NOT NULL AND phm.AnswerCount > 0 AND phm.AcceptedAnswerId IS NULL THEN 'Unanswered with Answers'
        WHEN phm.PostTypeId = 1 AND phm.AnswerCount IS NULL AND phm.ViewCount > 100 THEN 'HighView NoAnswers'
        WHEN phm.ClosedDate IS NOT NULL AND phm.TotalReopenEvents = 0 THEN 'Permanently Closed'
        ELSE 'Active/Resolved'
    END AS PostStatusCategory,
    (phm.PostCreationDate - uas.UserCreationDate) AS PostAgeRelativeToUserCreation,
    (
        SELECT COUNT(DISTINCT b_corr.Id)
        FROM Badges AS b_corr
        WHERE b_corr.UserId = uas.UserId
          AND b_corr.Class = 1
          AND (b_corr.Date > uas.FirstAcceptedAnswerDate OR uas.FirstAcceptedAnswerDate IS NULL)
          AND b_corr.Date < phm.PostCreationDate
    ) AS GoldBadgesBeforePostCreation,
    LEAD(phm.Score, 1, 0) OVER (PARTITION BY uas.UserId ORDER BY phm.PostCreationDate) - phm.Score AS ScoreDifferenceToNextPost,
    NULLIF(phm.TotalEditEvents, 0) AS EditsIfAny
FROM UserActivitySummary AS uas
JOIN PostHistoricalMetrics AS phm ON uas.UserId = phm.OwnerUserId
LEFT JOIN Posts AS q_acc_post ON phm.AcceptedAnswerId = q_acc_post.Id
LEFT JOIN ProcessedTags AS pt ON phm.PostId = pt.PostId
WHERE
    uas.Reputation >= 5000
    AND phm.PostTypeId IN (1, 2)
    AND phm.Score >= 10
    AND phm.ViewCount >= 500
    AND (phm.FavoriteCount IS NULL OR phm.FavoriteCount >= 5)
    AND phm.PostCreationDate BETWEEN DATE '2019-01-01' AND DATE '2023-12-31'
    AND (phm.ClosedDate IS NULL OR phm.TotalReopenEvents > 0)
    AND EXISTS (
        SELECT 1
        FROM PostHistory AS ph_check
        WHERE ph_check.PostId = phm.PostId
          AND ph_check.PostHistoryTypeId IN (5, 8)
          AND ph_check.CreationDate BETWEEN phm.PostCreationDate AND phm.LastActivityDate
          AND ph_check.Comment IS NOT NULL
          AND LENGTH(TRIM(ph_check.Comment)) > 10
          AND ph_check.UserId IS NOT NULL
    )
    AND NOT (phm.Title LIKE '%[Deprecated]%' OR LOWER(phm.Title) LIKE '%old version%')
    AND phm.LastActivityDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
GROUP BY
    uas.UserId, uas.DisplayName, uas.Reputation, uas.TotalQuestionsByOwner, uas.TotalAnswersByOwner,
    uas.TotalPostScoreByOwner, uas.AvgPostScoreByOwner, uas.UserCreationDate, uas.FirstAcceptedAnswerDate,
    phm.PostId, phm.PostTypeName, phm.Title, phm.Score, phm.ViewCount, phm.AnswerCount, phm.CommentCount,
    phm.FavoriteCount, phm.AvgCommentScore, phm.TotalEditEvents, phm.TotalClosureEvents, phm.TotalReopenEvents,
    phm.TotalBountyAmount, phm.ViewCountQuartile, phm.RankByOwnerScore, phm.PostTypeId, phm.AcceptedAnswerId,
    q_acc_post.Score, q_acc_post.ViewCount, phm.LastActivityDate, phm.ClosedDate, phm.PostCreationDate
HAVING
    COUNT(DISTINCT pt.TagName) > 2
    AND SUM(CASE WHEN pt.TagName IN ('sql-server', 'postgresql', 'mysql', 'database', 'nosql', 'mongodb') THEN 1 ELSE 0 END) >= 1
    AND (phm.PostTypeId = 1 OR (phm.PostTypeId = 2 AND phm.Score > phm.AvgCommentScore * 2))
ORDER BY
    uas.Reputation DESC,
    WeightedEngagementScore DESC,
    phm.PostCreationDate ASC
LIMIT 5000;