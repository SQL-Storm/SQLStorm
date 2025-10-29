WITH UserCoreStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COALESCE(u.Location, 'Unspecified Location') AS Location,
        SUBSTRING(COALESCE(u.AboutMe, 'No "About Me" provided.') FROM 1 FOR 200) AS AboutMeSnippet,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(p.Score) AS TotalPostScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        AVG(CASE WHEN p.PostTypeId IN (1,2) THEN p.Score ELSE NULL END) AS AvgQuestionAnswerScore,
        MAX(b.Date) AS LatestBadgeDate,
        COUNT(DISTINCT b.Id) AS TotalBadges
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes, u.Location, u.AboutMe
),
PostActivityLog AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS EventDate,
        ph.UserId AS EventUserId,
        ph.PostHistoryTypeId,
        pht.Name AS EventTypeName,
        ph.Comment,
        ph.Text,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn_type_event,
        LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousEventDate_Overall
    FROM PostHistory AS ph
    JOIN PostHistoryTypes AS pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 8)
    UNION ALL
    SELECT
        ph.PostId,
        ph.CreationDate AS EventDate,
        ph.UserId AS EventUserId,
        ph.PostHistoryTypeId,
        pht.Name AS EventTypeName,
        ph.Comment,
        ph.Text,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn_type_event,
        LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousEventDate_Overall
    FROM PostHistory AS ph
    JOIN PostHistoryTypes AS pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId = 10
    UNION ALL
    SELECT
        ph.PostId,
        ph.CreationDate AS EventDate,
        ph.UserId AS EventUserId,
        ph.PostHistoryTypeId,
        pht.Name AS EventTypeName,
        ph.Comment,
        ph.Text,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn_type_event,
        LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousEventDate_Overall
    FROM PostHistory AS ph
    JOIN PostHistoryTypes AS pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId = 11
),
PostEditDetails AS (
    -- Replace COUNT(DISTINCT ...) OVER (...) with an aggregate in a sub-aggregation per post
    SELECT
        pal.PostId,
        pal.EventDate AS EditDate,
        pal.EventUserId AS EditorUserId,
        ROW_NUMBER() OVER (PARTITION BY pal.PostId ORDER BY pal.EventDate DESC) AS rn_latest_edit,
        LAG(pal.EventDate) OVER (PARTITION BY pal.PostId ORDER BY pal.EventDate) AS PreviousEditDate_Specific,
        ped.DistinctEditorCount,
        ped.TotalEditCount
    FROM PostActivityLog AS pal
    JOIN (
        SELECT
            pal2.PostId,
            COUNT(DISTINCT pal2.EventUserId) AS DistinctEditorCount,
            COUNT(*) AS TotalEditCount
        FROM PostActivityLog pal2
        WHERE pal2.PostHistoryTypeId IN (4,5,6,8)
        GROUP BY pal2.PostId
    ) ped ON pal.PostId = ped.PostId
    WHERE pal.PostHistoryTypeId IN (4, 5, 6, 8)
),
PostClosureDetails AS (
    SELECT
        pal.PostId,
        pal.EventDate AS CloseDate,
        pal.EventUserId AS CloserUserId,
        cr.Name AS CloseReason,
        pal.rn_type_event AS rn_latest_close
    FROM PostActivityLog AS pal
    JOIN CloseReasonTypes AS cr ON CAST(pal.Comment AS integer) = cr.Id
    WHERE pal.PostHistoryTypeId = 10
      AND pal.rn_type_event = 1
),
TaggedPostDetails AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.LastActivityDate,
        LOWER(UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><'))) AS TagName,
        p.PostTypeId
    FROM Posts AS p
    WHERE p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
      AND (LOWER(p.Tags) LIKE '%<sql>%' OR LOWER(p.Tags) LIKE '%<database>%')
),
RankedUserQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Title AS QuestionTitle,
        p.ViewCount,
        p.Score,
        p.AnswerCount,
        p.CreationDate AS QuestionCreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC, p.Score DESC) AS UserQuestionRank
    FROM Posts AS p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
),
WeightedVoteSummary AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVotes,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountyGiven
    FROM Votes AS v
    GROUP BY v.PostId
)
SELECT
    ucs.UserId,
    ucs.DisplayName,
    ucs.Reputation,
    ucs.Location,
    ucs.AboutMeSnippet,
    ucs.TotalPosts,
    ucs.QuestionCount,
    ucs.AnswerCount,
    ucs.TotalComments,
    ucs.AvgQuestionAnswerScore,
    ucs.TotalBadges,
    -- Standard SQL timestamp functions used
    TIMESTAMP '2024-10-01 12:34:56' - ucs.CreationDate AS AccountAge,
    EXTRACT(DAY FROM (TIMESTAMP '2024-10-01 12:34:56' - ucs.LastAccessDate)) AS DaysSinceLastAccess,
    COALESCE(ucs.LatestBadgeDate, ucs.CreationDate) AS ActivityStartDate,
    SUM(COALESCE(ws.UpVotesReceived, 0)) AS TotalPostUpvotesReceived,
    SUM(COALESCE(ws.DownVotesReceived, 0)) AS TotalPostDownvotesReceived,
    CAST(SUM(COALESCE(ws.UpVotesReceived, 0)) AS NUMERIC) / NULLIF(SUM(COALESCE(ws.DownVotesReceived, 0)), 0) AS UpvoteDownvoteRatio,
    (ucs.UpVotes - ucs.DownVotes + ucs.TotalComments * 0.5 + ucs.QuestionCount * 2 + ucs.AnswerCount * 1.5 + SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.OwnerUserId = ucs.UserId THEN 5 ELSE 0 END) + SUM(COALESCE(ws.AcceptedVotes,0)) * 3) AS CalculatedInfluenceScore,
    CASE
        WHEN ucs.Reputation >= 10000 AND ucs.QuestionCount >= 5 AND ucs.AnswerCount >= 10 THEN 'High Contributor'
        WHEN ucs.Reputation >= 1000 AND ucs.QuestionCount >= 2 AND ucs.AnswerCount >= 2 THEN 'Active Participant'
        ELSE 'Casual User'
    END AS UserContributionLevel,
    STRING_AGG(DISTINCT tpd.TagName, ', ') FILTER (WHERE tpd.PostTypeId IN (1,2)) AS TagsOfParticipation,
    MAX(CASE WHEN rqu.UserQuestionRank = 1 THEN rqu.QuestionTitle ELSE NULL END) AS MostViewedQuestionTitle,
    MAX(CASE WHEN rqu.UserQuestionRank = 1 THEN rqu.ViewCount ELSE NULL END) AS MostViewedQuestionViews,
    COUNT(DISTINCT pe.PostId) FILTER (WHERE pe.DistinctEditorCount >= 2 AND pe.EditorUserId <> ucs.UserId) AS PostsEditedByOthersCount,
    MAX(pe.EditDate) FILTER (WHERE pe.rn_latest_edit = 1 AND pe.EditorUserId = ucs.UserId) AS LatestSelfEditDate,
    MAX(pe.EditDate) FILTER (WHERE pe.rn_latest_edit = 1 AND pe.EditorUserId <> ucs.UserId) AS LatestOtherEditDate,
    AVG(EXTRACT(EPOCH FROM (pe.EditDate - pe.PreviousEditDate_Specific))) * INTERVAL '1 second' AS AvgTimeBetweenEditsForOwnPosts,
    COUNT(DISTINCT pcd.PostId) AS TotalClosedPostsByUser,
    STRING_AGG(DISTINCT pcd.CloseReason, '; ') FILTER (WHERE pcd.rn_latest_close = 1) AS LatestPostCloseReasons
FROM UserCoreStats AS ucs
LEFT JOIN Posts AS p ON ucs.UserId = p.OwnerUserId
LEFT JOIN PostEditDetails AS pe ON p.Id = pe.PostId
LEFT JOIN TaggedPostDetails AS tpd ON ucs.UserId = tpd.OwnerUserId AND p.Id = tpd.PostId
LEFT JOIN RankedUserQuestions AS rqu ON ucs.UserId = rqu.OwnerUserId
LEFT JOIN WeightedVoteSummary AS ws ON p.Id = ws.PostId
LEFT JOIN PostClosureDetails AS pcd ON p.Id = pcd.PostId
WHERE ucs.QuestionCount >= 1
  AND ucs.AnswerCount >= 1
  AND ucs.Reputation > 500
  AND EXISTS (SELECT 1 FROM TaggedPostDetails tpd_inner WHERE tpd_inner.OwnerUserId = ucs.UserId AND tpd_inner.PostTypeId IN (1,2))
GROUP BY
    ucs.UserId, ucs.DisplayName, ucs.Reputation, ucs.Location, ucs.AboutMeSnippet, ucs.TotalPosts,
    ucs.QuestionCount, ucs.AnswerCount, ucs.TotalComments, ucs.AvgQuestionAnswerScore,
    ucs.TotalBadges, ucs.CreationDate, ucs.LastAccessDate, ucs.LatestBadgeDate, ucs.UpVotes, ucs.DownVotes,
    ucs.Views, ucs.LatestBadgeDate, ucs.CreationDate
HAVING
    COUNT(DISTINCT CASE WHEN pe.DistinctEditorCount >= 2 AND pe.EditorUserId <> ucs.UserId THEN pe.PostId ELSE NULL END) >= 1
ORDER BY CalculatedInfluenceScore DESC, ucs.Reputation DESC
LIMIT 10;