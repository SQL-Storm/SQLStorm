WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 AS Level
    FROM Tags t
    WHERE t.IsRequired = TRUE

    UNION ALL

    SELECT 
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        rh.Level + 1
    FROM Tags child
    JOIN RecursiveTagHierarchy rh ON child.WikiPostId = rh.ExcerptPostId
    WHERE rh.Level < 3
),
UserBadgeCounts AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
PostScoreRank AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate ASC) AS ScoreRank,
        COUNT(*) OVER (PARTITION BY p.PostTypeId) AS TotalPostsOfType
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
PostWithAcceptedAnswer AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.Tags,
        q.OwnerUserId AS QuestionOwner,
        q.CreationDate AS QuestionCreation,
        q.Score AS QuestionScore,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwner,
        a.CreationDate AS AnswerCreation,
        a.Score AS AnswerScore,
        a.ParentId,
        a.Body,
        q.ViewCount,
        q.FavoriteCount,
        q.CommentCount
    FROM Posts q
    LEFT JOIN Posts a ON a.Id = q.AcceptedAnswerId
    WHERE q.PostTypeId = 1
),
UserActivitySummary AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TotalBadges,
        COALESCE(pqs.QuestionCount, 0) AS QuestionCount,
        COALESCE(pas.AnswerCount, 0) AS AnswerCount,
        COALESCE(cmt.CommentCount, 0) AS CommentCount
    FROM Users u
    LEFT JOIN UserBadgeCounts ub ON ub.UserId = u.Id
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS QuestionCount
        FROM Posts
        WHERE PostTypeId = 1
        GROUP BY OwnerUserId
    ) pqs ON pqs.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS AnswerCount
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY OwnerUserId
    ) pas ON pas.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY UserId
    ) cmt ON cmt.UserId = u.Id
),
HighImpactPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        CASE 
            WHEN p.ViewCount > 10000 THEN 'High View'
            WHEN p.Score > 100 THEN 'High Score'
            WHEN p.FavoriteCount > 50 THEN 'Highly Favorited'
            ELSE 'Normal'
        END AS ImpactCategory
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
DuplicateLinkedPosts AS (
    SELECT DISTINCT pl.PostId, pl.RelatedPostId
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE lt.Name = 'Duplicate'
),
PostsWithCloseReason AS (
    SELECT 
        ph.PostId,
        crt.Name AS CloseReasonName,
        ph.CreationDate AS CloseDate
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
    JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INTEGER)
    WHERE pht.Name = 'Post Closed' AND ph.Comment IS NOT NULL
),
PostsWithVotesSummary AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE 0 END) AS FavoriteVotes,
        COUNT(*) AS TotalVotes
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
FinalSelection AS (
    SELECT 
        pwa.QuestionId,
        pwa.Title,
        pwa.Tags,
        pwa.QuestionOwner,
        ua.DisplayName AS QuestionOwnerName,
        ua.Reputation AS QuestionOwnerReputation,
        pwa.AnswerId,
        ua2.DisplayName AS AnswerOwnerName,
        ua2.Reputation AS AnswerOwnerReputation,
        pwa.AnswerScore,
        pwa.QuestionScore,
        pwa.ViewCount,
        pwa.FavoriteCount,
        pwa.CommentCount,
        ps.ImpactCategory,
        pclose.CloseReasonName,
        pclose.CloseDate,
        dup.RelatedPostId AS DuplicateOf,
        vts.UpVotes,
        vts.DownVotes,
        vts.FavoriteVotes,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.TotalBadges,
        ROW_NUMBER() OVER (PARTITION BY pwa.QuestionOwner ORDER BY pwa.QuestionScore DESC, pwa.ViewCount DESC) AS UserQuestionRank,
        COUNT(*) OVER (PARTITION BY pwa.QuestionOwner) AS UserTotalQuestions
    FROM PostWithAcceptedAnswer pwa
    LEFT JOIN UserActivitySummary ua ON ua.Id = pwa.QuestionOwner
    LEFT JOIN UserActivitySummary ua2 ON ua2.Id = pwa.AnswerOwner
    LEFT JOIN HighImpactPosts ps ON ps.Id = pwa.QuestionId
    LEFT JOIN PostsWithCloseReason pclose ON pclose.PostId = pwa.QuestionId
    LEFT JOIN DuplicateLinkedPosts dup ON dup.PostId = pwa.QuestionId
    LEFT JOIN PostsWithVotesSummary vts ON vts.PostId = pwa.QuestionId
    LEFT JOIN UserBadgeCounts us ON us.UserId = pwa.QuestionOwner
    WHERE pwa.AnswerId IS NOT NULL
)
SELECT 
    fs.QuestionId,
    fs.Title,
    fs.Tags,
    fs.QuestionOwner,
    fs.QuestionOwnerName,
    fs.QuestionOwnerReputation,
    fs.AnswerId,
    fs.AnswerOwnerName,
    fs.AnswerOwnerReputation,
    fs.AnswerScore,
    fs.QuestionScore,
    fs.ViewCount,
    fs.FavoriteCount,
    fs.CommentCount,
    fs.ImpactCategory,
    COALESCE(fs.CloseReasonName, 'Open') AS CloseReason,
    fs.CloseDate,
    fs.DuplicateOf,
    fs.UpVotes,
    fs.DownVotes,
    fs.FavoriteVotes,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.TotalBadges,
    fs.UserQuestionRank,
    fs.UserTotalQuestions,
    CASE 
        WHEN fs.QuestionOwnerReputation > 50000 THEN 'Elite'
        WHEN fs.QuestionOwnerReputation BETWEEN 10000 AND 50000 THEN 'Experienced'
        ELSE 'Newbie'
    END AS UserReputationClass,
    LENGTH(fs.Title) AS TitleLength,
    COALESCE(NULLIF(fs.Tags, ''), '<no-tags>') AS TagsOrNone,
    ('Q#' || fs.QuestionId || '-A#' || fs.AnswerId) AS QnA_CompositeId
FROM FinalSelection fs
WHERE 
    fs.UserQuestionRank <= 5
    AND (fs.ImpactCategory = 'High View' OR fs.ImpactCategory = 'High Score' OR fs.ImpactCategory = 'Highly Favorited')
ORDER BY 
    fs.QuestionOwnerReputation DESC,
    fs.QuestionScore DESC,
    fs.ViewCount DESC;