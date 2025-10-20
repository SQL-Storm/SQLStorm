WITH RECURSIVE RecursivePostHierarchy AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        1 AS Depth
    FROM Posts p
    WHERE p.PostTypeId = 1
    UNION ALL
    SELECT 
        c.Id,
        c.PostTypeId,
        c.ParentId,
        c.OwnerUserId,
        c.CreationDate,
        c.Score,
        c.ViewCount,
        c.Title,
        c.Tags,
        r.Depth + 1
    FROM Posts c
    JOIN RecursivePostHierarchy r ON c.ParentId = r.Id
    WHERE c.PostTypeId = 2
),
LatestUserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.WebsiteUrl,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        MAX(ph.CreationDate) AS LastEditDate
    FROM Users u
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.WebsiteUrl, u.Views, u.UpVotes, u.DownVotes
),
PostVotesSummary AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE 0 END) AS Favorites,
        SUM(COALESCE(v.BountyAmount,0)) AS TotalBounty
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
TagUsage AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS QuestionCount,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastQuestionDate
    FROM Tags t
    LEFT JOIN Posts p ON p.PostTypeId = 1
        AND p.Tags LIKE ('%' || '<' || t.TagName || '>' || '%')
    GROUP BY t.TagName
),
UserBadgeSummary AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges,
        BOOL_OR(b.TagBased) AS HasTagBasedBadge
    FROM Badges b
    GROUP BY b.UserId
),
QuestionCloseReasons AS (
    SELECT 
        ph.PostId,
        crt.Name AS CloseReasonName,
        ph.CreationDate AS CloseDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId AND pht.Name = 'Post Closed'
    LEFT JOIN CloseReasonTypes crt ON CAST(crt.Id AS VARCHAR) = ph.Comment
    WHERE ph.PostId IS NOT NULL
),
TopActiveUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COUNT(p.Id) AS PostsCount,
        COALESCE(SUM(p.Score),0) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(p.Id) > 20
),
RecentCommentsOnPopularAnswers AS (
    SELECT 
        c.PostId,
        c.Id AS CommentId,
        c.Score AS CommentScore,
        c.Text AS CommentText,
        c.CreationDate AS CommentDate,
        p.Id AS AnswerId,
        p.Score AS AnswerScore,
        p.ParentId AS QuestionId,
        u.DisplayName AS CommenterName,
        c.UserId AS CommenterId
    FROM Comments c
    JOIN Posts p ON p.Id = c.PostId AND p.PostTypeId = 2 AND p.Score > 10
    LEFT JOIN Users u ON u.Id = c.UserId
    WHERE c.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY)
),
BaseQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        cr.CloseReasonName,
        cr.CloseDate,
        p.OwnerUserId
    FROM Posts p
    LEFT JOIN (
        SELECT PostId, CloseReasonName, CloseDate
        FROM QuestionCloseReasons
        WHERE rn = 1
    ) cr ON cr.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.Score > 5
      AND p.ViewCount > 1000
),
QuestionMain AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViews,
        pvs.UpVotes AS QuestionUpVotes,
        pvs.DownVotes AS QuestionDownVotes,
        pvs.Favorites AS QuestionFavorites,
        pvs.TotalBounty AS QuestionBounty,
        lur.DisplayName AS QuestionOwner,
        lur.Reputation AS OwnerReputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        q.CloseReasonName,
        q.CloseDate,
        ans.AnswerCount,
        ans.TopAnswerId,
        ans.TopAnswerScore,
        ans.TopAnswerOwner,
        ans.TopAnswerOwnerReputation,
        cmt.CommentCount,
        cmt.LatestCommentText,
        cmt.LatestCommenter,
        cmt.LatestCommentDate
    FROM BaseQuestions q
    LEFT JOIN PostVotesSummary pvs ON pvs.PostId = q.Id
    LEFT JOIN LatestUserActivity lur ON lur.UserId = q.OwnerUserId
    LEFT JOIN UserBadgeSummary ub ON ub.UserId = q.OwnerUserId
    LEFT JOIN LATERAL (
        SELECT 
            COUNT(*) AS AnswerCount,
            MAX(a.Score) AS TopAnswerScore,
            MAX(a.Id) FILTER (WHERE a.Score = max_score) AS TopAnswerId,
            MAX(u.DisplayName) FILTER (WHERE a.Score = max_score) AS TopAnswerOwner,
            MAX(u.Reputation) FILTER (WHERE a.Score = max_score) AS TopAnswerOwnerReputation
        FROM (
            SELECT a.*, MAX(a.Score) OVER () AS max_score
            FROM Posts a
            WHERE a.ParentId = q.Id AND a.PostTypeId = 2
        ) a
        LEFT JOIN Users u ON u.Id = a.OwnerUserId
    ) ans ON TRUE
    LEFT JOIN LATERAL (
        SELECT 
            COUNT(*) AS CommentCount,
            MAX(c.Text) AS LatestCommentText,
            MAX(u.DisplayName) AS LatestCommenter,
            MAX(c.CreationDate) AS LatestCommentDate
        FROM Comments c
        LEFT JOIN Users u ON u.Id = c.UserId
        WHERE c.PostId = q.Id
    ) cmt ON TRUE
    WHERE (q.CloseDate IS NULL OR q.CloseDate > (CAST('2024-10-01' AS DATE) - INTERVAL '90' DAY))
),
QuestionMainLimited AS (
    SELECT *
    FROM QuestionMain
    ORDER BY QuestionViews DESC, QuestionScore DESC
    LIMIT 50
),
RecentCommentsLimited AS (
    SELECT
        r.PostId AS QuestionId,
        CAST(NULL AS VARCHAR) AS QuestionTitle,
        CAST(NULL AS TIMESTAMP) AS QuestionCreationDate,
        CAST(NULL AS INTEGER) AS QuestionScore,
        CAST(NULL AS INTEGER) AS QuestionViews,
        CAST(NULL AS INTEGER) AS QuestionUpVotes,
        CAST(NULL AS INTEGER) AS QuestionDownVotes,
        CAST(NULL AS INTEGER) AS QuestionFavorites,
        CAST(NULL AS NUMERIC) AS QuestionBounty,
        r.CommenterName AS QuestionOwner,
        CAST(NULL AS INTEGER) AS OwnerReputation,
        CAST(NULL AS INTEGER) AS GoldBadges,
        CAST(NULL AS INTEGER) AS SilverBadges,
        CAST(NULL AS INTEGER) AS BronzeBadges,
        CAST(NULL AS VARCHAR) AS CloseReasonName,
        CAST(NULL AS TIMESTAMP) AS CloseDate,
        CAST(NULL AS INTEGER) AS AnswerCount,
        CAST(NULL AS INTEGER) AS TopAnswerId,
        CAST(NULL AS INTEGER) AS TopAnswerScore,
        CAST(NULL AS VARCHAR) AS TopAnswerOwner,
        CAST(NULL AS INTEGER) AS TopAnswerOwnerReputation,
        CAST(NULL AS INTEGER) AS CommentCount,
        r.CommentText AS LatestCommentText,
        r.CommenterName AS LatestCommenter,
        r.CommentDate AS LatestCommentDate
    FROM RecentCommentsOnPopularAnswers r
    LEFT JOIN Users u ON u.Id = r.CommenterId
    ORDER BY r.CommentDate DESC
    LIMIT 20
)
SELECT *
FROM QuestionMainLimited

UNION ALL

SELECT *
FROM RecentCommentsLimited;