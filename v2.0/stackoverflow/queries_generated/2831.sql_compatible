WITH RecursiveUserBadges AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        b.Name AS BadgeName,
        b.Class,
        b.Date,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Date DESC) AS rn
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON b.UserId = u.Id
    WHERE 
        u.Reputation > 1000
),
FilteredBadges AS (
    SELECT UserId, DisplayName, BadgeName, Class, Date
    FROM RecursiveUserBadges
    WHERE rn <= 5
),
TopPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(NULLIF(p.Tags, ''), '<tagless>') AS SanitizedTags,
        -- Aggregate owner display names per post (standard SQL: use STRING_AGG in a grouped subquery)
        owners.OwnerDisplayNames,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank
    FROM 
        Posts p
    LEFT JOIN 
        (
            SELECT p2.Id AS PostId, STRING_AGG(COALESCE(u2.DisplayName, 'Anonymous'), ', ' ORDER BY u2.Reputation DESC) AS OwnerDisplayNames
            FROM Posts p2
            LEFT JOIN Users u2 ON u2.Id = p2.OwnerUserId
            WHERE p2.PostTypeId IN (1,2)
            GROUP BY p2.Id
        ) owners ON owners.PostId = p.Id
    WHERE 
        p.PostTypeId IN (1,2) 
        AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '365 day'
),
PostWithAnswers AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionDate,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViews,
        q.SanitizedTags,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerDate,
        a.OwnerUserId AS AnswerOwnerUserId,
        a.Title AS AnswerTitle,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600 AS HoursToAnswer
    FROM 
        TopPosts q
    LEFT JOIN 
        Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE 
        q.PostTypeId = 1
),
PostLinkStats AS (
    SELECT 
        pl.PostId,
        pl.LinkTypeId,
        COUNT(*) AS LinkCount,
        MAX(pl.CreationDate) AS LastLinkDate
    FROM 
        PostLinks pl
    GROUP BY 
        pl.PostId, pl.LinkTypeId
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsPosted,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersPosted,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        SUM(vt_wt.Weight) AS VoteWeightSum,
        MAX(u.LastAccessDate) AS LastAccess
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON c.UserId = u.Id
    LEFT JOIN 
        Votes v ON v.UserId = u.Id
    LEFT JOIN
        VoteTypes vt ON vt.Id = v.VoteTypeId
    LEFT JOIN
        (VALUES
            (1, 5),  (2, 3),  (3, -1), (4, -2), (5, 1),
            (6, 0),  (7, 2),  (8, 4),  (9, 4),  (10, -5),
            (11, 5), (12, -10),(14, 1), (15, 1), (16, 2)
        ) AS vt_wt(id, weight) ON vt_wt.id = vt.Id
    GROUP BY 
        u.Id, u.DisplayName
),
BadgeCounts AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM 
        Badges
    GROUP BY 
        UserId
),
UserEngagement AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        COALESCE(bc.GoldBadges, 0) AS GoldBadges,
        COALESCE(bc.SilverBadges, 0) AS SilverBadges,
        COALESCE(bc.BronzeBadges, 0) AS BronzeBadges,
        ua.VoteWeightSum,
        ua.LastAccess,
        COALESCE(ua.QuestionsPosted * 2,0) 
        + COALESCE(ua.AnswersPosted * 3,0) 
        + COALESCE(ua.CommentsMade * 1,0)
        + COALESCE(bc.GoldBadges * 10,0)
        + COALESCE(bc.SilverBadges * 5,0)
        + COALESCE(bc.BronzeBadges * 2,0)
        + COALESCE(ua.VoteWeightSum, 0) AS EngagementScore
    FROM 
        UserActivity ua
    LEFT JOIN 
        BadgeCounts bc ON bc.UserId = ua.UserId
),
RecentCloseVotes AS (
    SELECT 
        ph.PostId,
        cr.Name AS CloseReason,
        COUNT(*) AS CloseVoteCount,
        MAX(ph.CreationDate) AS LastCloseVoteDate
    FROM 
        PostHistory ph
    LEFT JOIN 
        CloseReasonTypes cr ON cr.Id = CAST(ph.Comment AS SMALLINT)
    WHERE 
        ph.PostHistoryTypeId = 10
        AND ph.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
    GROUP BY 
        ph.PostId, cr.Name
),
AnswerSentiments AS (
    SELECT 
        a.ParentId AS QuestionId,
        AVG(
            CASE 
                WHEN a.Score >= 10 THEN 1 
                WHEN a.Score BETWEEN 0 AND 9 THEN 0 
                ELSE -1 
            END
        ) AS AvgSentiment
    FROM 
        Posts a
    WHERE 
        a.PostTypeId = 2
    GROUP BY 
        a.ParentId
),
QuestionsCombined AS (
    SELECT 
        q.QuestionId,
        q.QuestionTitle,
        q.QuestionDate,
        q.QuestionScore,
        q.QuestionViews,
        q.SanitizedTags,
        q.AnswerId,
        q.AnswerScore,
        q.AnswerDate,
        q.AnswerOwnerUserId,
        q.AnswerTitle,
        q.HoursToAnswer,
        pcs.LinkCount AS DuplicateLinkCount,
        pc.CloseVoteCount,
        pc.CloseReason,
        asent.AvgSentiment,
        ue.EngagementScore AS QuestionOwnerEngagement,
        ue.DisplayName AS QuestionOwnerName
    FROM 
        PostWithAnswers q
    LEFT JOIN 
        PostLinkStats pcs ON pcs.PostId = q.QuestionId AND pcs.LinkTypeId = 3
    LEFT JOIN 
        RecentCloseVotes pc ON pc.PostId = q.QuestionId
    LEFT JOIN 
        AnswerSentiments asent ON asent.QuestionId = q.QuestionId
    LEFT JOIN 
        UserEngagement ue ON ue.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = q.QuestionId)
)
SELECT
    qc.QuestionId,
    qc.QuestionTitle,
    qc.QuestionDate,
    qc.QuestionScore,
    qc.QuestionViews,
    qc.SanitizedTags,
    qc.AnswerId,
    qc.AnswerScore,
    qc.AnswerDate,
    qc.AnswerOwnerUserId,
    COALESCE(ub.DisplayName, 'Unknown') AS AnswerOwnerName,
    qc.AnswerTitle,
    qc.HoursToAnswer,
    COALESCE(qc.DuplicateLinkCount, 0) AS DuplicateLinks,
    qc.CloseVoteCount,
    qc.CloseReason,
    ROUND(COALESCE(qc.AvgSentiment, 0),2) AS AverageAnswerSentiment,
    qc.QuestionOwnerEngagement,
    qc.QuestionOwnerName,
    REPLACE(REPLACE(qc.SanitizedTags, '><', ', '), '<', '') AS TagsList,
    RANK() OVER (ORDER BY qc.QuestionScore DESC, qc.QuestionViews DESC) AS OverallRank
FROM 
    QuestionsCombined qc
LEFT JOIN 
    Users ub ON ub.Id = qc.AnswerOwnerUserId
WHERE 
    qc.QuestionDate >= CAST('2024-10-01' AS date) - INTERVAL '1 year'
    AND (qc.CloseVoteCount IS NULL OR qc.CloseVoteCount < 3)
    AND qc.QuestionOwnerEngagement > 50
ORDER BY 
    OverallRank
LIMIT 50;