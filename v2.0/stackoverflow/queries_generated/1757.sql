-- {"query": "1757.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3451} 

WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        COUNT(DISTINCT p_ans.Id) AS AnswersGiven,
        AVG(p_ans.Score) AS AvgAnswerScore,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        SUM(v_up.BountyAmount) AS BountyReceivedTotal,
        MAX(u.LastAccessDate) AS LastSeen
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p_ans ON u.Id = p_ans.OwnerUserId AND p_ans.PostTypeId = 2 -- Answers
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v_up ON u.Id = v_up.UserId AND v_up.VoteTypeId IN (8, 9) -- BountyStart (8) or BountyClose (9)
    GROUP BY u.Id, u.Reputation
),
QuestionMetrics AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        p.AcceptedAnswerId,
        p.Title,
        p.Tags,
        p.Body,
        p.CommunityOwnedDate,
        p.LastEditDate,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><') AS TagArray,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_owner_latest_question
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions only
),
PostHistoryDetails AS (
    SELECT
        ph.Id AS HistoryId,
        ph.PostId,
        ph.CreationDate AS HistoryDate,
        ph.UserId AS HistoryUserId,
        ph.PostHistoryTypeId,
        LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PrevHistoryDate,
        ph.Comment,
        CASE
            WHEN ph.PostHistoryTypeId = 10 AND ph.Comment IN ('1', '101') THEN 'DuplicateClose' -- Old/New duplicate close reason
            WHEN ph.PostHistoryTypeId = 10 THEN 'OtherClose'
            WHEN ph.PostHistoryTypeId = 11 THEN 'Reopen'
            WHEN ph.PostHistoryTypeId IN (2, 5) THEN 'BodyEdit'
            ELSE 'OtherHistory'
        END AS HistoryEventType
    FROM PostHistory ph
),
PostHistoryAggregates AS (
    SELECT
        phd.PostId,
        COUNT(DISTINCT phd.HistoryUserId) AS DistinctEditors,
        MAX(CASE WHEN phd.HistoryEventType = 'DuplicateClose' THEN phd.HistoryDate END) AS DuplicateCloseDate,
        MAX(CASE WHEN phd.HistoryEventType = 'OtherClose' THEN phd.HistoryDate END) AS OtherCloseDate,
        MAX(CASE WHEN phd.HistoryEventType = 'Reopen' THEN phd.HistoryDate END) AS ReopenDate,
        SUM(CASE WHEN phd.HistoryEventType = 'BodyEdit' THEN 1 ELSE 0 END) AS BodyEditCount,
        AVG(EXTRACT(EPOCH FROM (phd.HistoryDate - phd.PrevHistoryDate)) / 3600.0) FILTER (WHERE phd.HistoryEventType = 'BodyEdit' AND phd.PrevHistoryDate IS NOT NULL) AS AvgEditIntervalHours
    FROM PostHistoryDetails phd
    GROUP BY phd.PostId
),
RecentCommentsPerPost AS (
    SELECT
        c.PostId,
        MAX(c.CreationDate) AS LatestCommentDate,
        SUBSTRING(
            MAX(TO_CHAR(c.CreationDate, 'YYYYMMDDHH24MISS') || c.Text)
            OVER (PARTITION BY c.PostId), 15
        ) AS LatestCommentText
    FROM Comments c
    GROUP BY c.PostId
),
DuplicateLinkInfo AS (
    SELECT
        pl.PostId,
        ARRAY_AGG(DISTINCT pl.RelatedPostId) FILTER (WHERE lt.Name = 'Duplicate') AS DuplicatesOfThisPost,
        ARRAY_AGG(DISTINCT pl.RelatedPostId) FILTER (WHERE lt.Name = 'Linked') AS LinkedPosts
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
),
ModeratorActivity AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.UserId) AS ModeratorActionsCount,
        MAX(ph.CreationDate) AS LastModeratorActionDate,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (14, 19) THEN 1 ELSE 0 END) AS ProtectionLocks
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (14, 15, 19, 20) -- Lock/Unlock, Protect/Unprotect
    GROUP BY ph.PostId
),
HighImpactQuestions AS (
    SELECT
        q.PostId,
        q.Title,
        q.Tags,
        u_owner.DisplayName AS OwnerDisplayName,
        ue.Reputation AS OwnerReputation,
        ue.TotalBadges AS OwnerTotalBadges,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViews,
        q.AnswerCount AS QuestionAnswers,
        q.FavoriteCount AS QuestionFavorites,
        q.CreationDate AS QuestionCreationDate,
        q.LastActivityDate,
        q.ClosedDate,
        COALESCE(q.CommunityOwnedDate, '1900-01-01 00:00:00'::timestamp) AS CommunityOwnedThreshold,
        q.TagArray,
        aa.Score AS AcceptedAnswerScore,
        aa_owner.DisplayName AS AcceptedAnswerOwner,
        DENSE_RANK() OVER (ORDER BY q.Score DESC, q.ViewCount DESC, q.AnswerCount DESC) AS GlobalPostRank,
        SUM(q.Score) OVER (PARTITION BY u_owner.Id) AS TotalOwnerPostScore,
        AVG(q.ViewCount) OVER (PARTITION BY u_owner.Id) AS AvgOwnerPostViews,
        pha.DistinctEditors,
        COALESCE(EXTRACT(EPOCH FROM (pha.ReopenDate - pha.DuplicateCloseDate)) / 3600.0, -1.0) AS HoursToReopenDuplicate,
        COALESCE(EXTRACT(EPOCH FROM (pha.ReopenDate - pha.OtherCloseDate)) / 3600.0, -1.0) AS HoursToReopenOther,
        CASE
            WHEN q.ClosedDate IS NOT NULL AND pha.DuplicateCloseDate IS NOT NULL THEN 'Closed_Duplicate'
            WHEN q.ClosedDate IS NOT NULL THEN 'Closed_Other'
            WHEN q.AcceptedAnswerId IS NOT NULL AND q.AnswerCount > 0 THEN 'Answered_Accepted'
            WHEN q.AnswerCount > 0 THEN 'Answered_NoAccepted'
            ELSE 'Unanswered'
        END AS QuestionStatus,
        COALESCE(rcp.LatestCommentDate, q.CreationDate) AS EffectiveLastActivity,
        rcp.LatestCommentText,
        LOWER(LEFT(q.Title, 1)) AS FirstLetterOfTitle,
        (SELECT COUNT(DISTINCT v.UserId)
         FROM Votes v
         WHERE v.PostId = q.PostId AND v.VoteTypeId = 2 AND v.UserId IS NOT NULL AND v.UserId != q.OwnerUserId) AS UpVotersCountExclOwner,
        (SELECT AVG(LENGTH(c_corr.Text))
         FROM Comments c_corr
         WHERE c_corr.PostId = q.PostId AND c_corr.CreationDate >= q.CreationDate + INTERVAL '1 month' AND LENGTH(c_corr.Text) > 10
        ) AS AvgCommentLengthAfterFirstMonth,
        dl.DuplicatesOfThisPost,
        dl.LinkedPosts,
        ma.ModeratorActionsCount,
        ma.ProtectionLocks,
        CASE
            WHEN ma.LastModeratorActionDate IS NOT NULL AND ma.LastModeratorActionDate > q.LastActivityDate THEN 'ModeratorIntervention'
            WHEN q.CreationDate BETWEEN '2023-01-01' AND '2023-12-31' THEN 'RecentQuestion'
            ELSE 'OlderQuestion'
        END AS QuestionAgeCategory,
        pha.BodyEditCount,
        pha.AvgEditIntervalHours,
        'HighImpact' AS QueryType
    FROM QuestionMetrics q
    LEFT JOIN Users u_owner ON q.OwnerUserId = u_owner.Id
    LEFT JOIN UserEngagement ue ON u_owner.Id = ue.UserId
    LEFT JOIN Posts aa ON q.AcceptedAnswerId = aa.Id
    LEFT JOIN Users aa_owner ON aa.OwnerUserId = aa_owner.Id
    LEFT JOIN PostHistoryAggregates pha ON q.PostId = pha.PostId
    LEFT JOIN RecentCommentsPerPost rcp ON q.PostId = rcp.PostId
    LEFT JOIN DuplicateLinkInfo dl ON q.PostId = dl.PostId
    LEFT JOIN ModeratorActivity ma ON q.PostId = ma.PostId
    WHERE
        q.rn_owner_latest_question = 1
        AND q.CreationDate >= '2022-01-01'
        AND q.ViewCount IS NOT NULL AND q.ViewCount > 0
        AND q.Score > 50
        AND q.AnswerCount > 3
        AND ue.Reputation > 10000
        AND NOT EXISTS (SELECT 1 FROM PostHistory WHERE PostId = q.PostId AND PostHistoryTypeId = 12) -- Exclude deleted posts
),
ModeratorOrEditedQuestions AS (
    SELECT
        q.PostId,
        q.Title,
        q.Tags,
        u_owner.DisplayName AS OwnerDisplayName,
        ue.Reputation AS OwnerReputation,
        ue.TotalBadges AS OwnerTotalBadges,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViews,
        q.AnswerCount AS QuestionAnswers,
        q.FavoriteCount AS QuestionFavorites,
        q.CreationDate AS QuestionCreationDate,
        q.LastActivityDate,
        q.ClosedDate,
        COALESCE(q.CommunityOwnedDate, '1900-01-01 00:00:00'::timestamp) AS CommunityOwnedThreshold,
        q.TagArray,
        aa.Score AS AcceptedAnswerScore,
        aa_owner.DisplayName AS AcceptedAnswerOwner,
        DENSE_RANK() OVER (ORDER BY q.LastActivityDate DESC, q.Score DESC) AS GlobalPostRank,
        SUM(q.Score) OVER (PARTITION BY u_owner.Id) AS TotalOwnerPostScore,
        AVG(q.ViewCount) OVER (PARTITION BY u_owner.Id) AS AvgOwnerPostViews,
        pha.DistinctEditors,
        COALESCE(EXTRACT(EPOCH FROM (pha.ReopenDate - pha.DuplicateCloseDate)) / 3600.0, -1.0) AS HoursToReopenDuplicate,
        COALESCE(EXTRACT(EPOCH FROM (pha.ReopenDate - pha.OtherCloseDate)) / 3600.0, -1.0) AS HoursToReopenOther,
        CASE
            WHEN q.ClosedDate IS NOT NULL AND pha.DuplicateCloseDate IS NOT NULL THEN 'Closed_Duplicate'
            WHEN q.ClosedDate IS NOT NULL THEN 'Closed_Other'
            WHEN q.AcceptedAnswerId IS NOT NULL AND q.AnswerCount > 0 THEN 'Answered_Accepted'
            WHEN q.AnswerCount > 0 THEN 'Answered_NoAccepted'
            ELSE 'Unanswered'
        END AS QuestionStatus,
        COALESCE(rcp.LatestCommentDate, q.CreationDate) AS EffectiveLastActivity,
        rcp.LatestCommentText,
        LOWER(LEFT(q.Title, 1)) AS FirstLetterOfTitle,
        (SELECT COUNT(DISTINCT v.UserId)
         FROM Votes v
         WHERE v.PostId = q.PostId AND v.VoteTypeId = 2 AND v.UserId IS NOT NULL AND v.UserId != q.OwnerUserId) AS UpVotersCountExclOwner,
        (SELECT AVG(LENGTH(c_corr.Text))
         FROM Comments c_corr
         WHERE c_corr.PostId = q.PostId AND c_corr.CreationDate >= q.CreationDate + INTERVAL '1 month' AND LENGTH(c_corr.Text) > 10
        ) AS AvgCommentLengthAfterFirstMonth,
        dl.DuplicatesOfThisPost,
        dl.LinkedPosts,
        ma.ModeratorActionsCount,
        ma.ProtectionLocks,
        CASE
            WHEN ma.LastModeratorActionDate IS NOT NULL AND ma.LastModeratorActionDate > q.LastActivityDate THEN 'ModeratorIntervention'
            WHEN q.CreationDate BETWEEN '2023-01-01' AND '2023-12-31' THEN 'RecentQuestion'
            ELSE 'OlderQuestion'
        END AS QuestionAgeCategory,
        pha.BodyEditCount,
        pha.AvgEditIntervalHours,
        'ModeratorOrEdited' AS QueryType
    FROM QuestionMetrics q
    LEFT JOIN Users u_owner ON q.OwnerUserId = u_owner.Id
    LEFT JOIN UserEngagement ue ON u_owner.Id = ue.UserId
    LEFT JOIN Posts aa ON q.AcceptedAnswerId = aa.Id
    LEFT JOIN Users aa_owner ON aa.OwnerUserId = aa_owner.Id
    LEFT JOIN PostHistoryAggregates pha ON q.PostId = pha.PostId
    LEFT JOIN RecentCommentsPerPost rcp ON q.PostId = rcp.PostId
    LEFT JOIN DuplicateLinkInfo dl ON q.PostId = dl.PostId
    LEFT JOIN ModeratorActivity ma ON q.PostId = ma.PostId
    WHERE
        q.rn_owner_latest_question = 1
        AND q.CreationDate >= '2022-01-01'
        AND (
            q.ClosedDate IS NOT NULL
            OR pha.DistinctEditors > 1
            OR ma.ModeratorActionsCount > 0
            OR pha.BodyEditCount > 2
        )
        AND NOT EXISTS (SELECT 1 FROM PostHistory WHERE PostId = q.PostId AND PostHistoryTypeId = 12)
)
SELECT * FROM HighImpactQuestions
UNION ALL
SELECT * FROM ModeratorOrEditedQuestions
ORDER BY GlobalPostRank ASC, EffectiveLastActivity DESC
LIMIT 2000;
