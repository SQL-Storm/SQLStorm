-- {"query": "4031.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2523}
WITH PostEditHistory AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate AS EditDate,
        pht.Name AS EditType,
        LEAD(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate) AS NextEditDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate) AS EditSequence
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(COALESCE(p.ViewCount, 0)) AS AvgPostViewCount,
        CASE
            WHEN SUM(COALESCE(p.AnswerCount,0)) > 0 THEN SUM(COALESCE(p.AnswerCount,0)) * 1.0 / COUNT(DISTINCT p.Id)
            ELSE 0
        END AS AvgAnswersPerQuestion,
        COUNT(DISTINCT c.Id) AS CommentCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        u.Reputation,
        u.CreationDate AS CreationDate,
        u.LastAccessDate,
        u.Location,
        u.WebsiteUrl
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.WebsiteUrl
),
PostMetrics AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        CASE WHEN p.CreationDate IS NOT NULL AND p.ClosedDate IS NOT NULL THEN CAST((EXTRACT(EPOCH FROM (p.ClosedDate - p.CreationDate)) / 60.0) AS INTEGER) ELSE NULL END AS MinutesToClose,
        CASE WHEN p.CreationDate IS NOT NULL AND p.ClosedDate IS NOT NULL THEN EXTRACT(EPOCH FROM (p.ClosedDate - p.CreationDate)) / 86400.0 ELSE NULL END AS DaysToClose,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) AS TotalInteractions,
        CASE
            WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3)
            ELSE 0
        END AS DuplicateLinksAsQuestion,
        CASE
            WHEN p.PostTypeId = 2 THEN (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = p.Id AND pl.LinkTypeId = 3)
            ELSE 0
        END AS DuplicateLinksAsAnswer,
        (SELECT SUM(Score) FROM Comments c WHERE c.PostId = p.Id) AS TotalCommentScore,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.UserId = p.OwnerUserId) AS OwnerCommentsCount,
        CASE
            WHEN EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 19) THEN 'Protected'
            ELSE 'Not Protected'
        END AS ProtectionStatus,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC) AS ViewRankByPostType
    FROM Posts p
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) AND p.Score > 0
),
UserEditStats AS (
    SELECT
        peh.UserId,
        COUNT(DISTINCT peh.PostId) AS EditedPostsCount,
        SUM(CASE WHEN peh.EditDate IS NOT NULL AND peh.NextEditDate IS NOT NULL THEN CAST((EXTRACT(EPOCH FROM (peh.NextEditDate - peh.EditDate)) / 60.0) AS INTEGER) ELSE 0 END) AS TotalEditTimeMinutes,
        AVG(CASE WHEN peh.EditDate IS NOT NULL AND peh.NextEditDate IS NOT NULL THEN CAST((EXTRACT(EPOCH FROM (peh.NextEditDate - peh.EditDate)) / 60.0) AS INTEGER) ELSE NULL END) AS AvgEditTimeMinutes,
        COUNT(DISTINCT CASE WHEN peh.EditType = 'Edit Title' THEN peh.PostId ELSE NULL END) AS TitleEdits,
        COUNT(DISTINCT CASE WHEN peh.EditType = 'Edit Body' THEN peh.PostId ELSE NULL END) AS BodyEdits,
        COUNT(DISTINCT CASE WHEN peh.EditType = 'Edit Tags' THEN peh.PostId ELSE NULL END) AS TagEdits
    FROM PostEditHistory peh
    GROUP BY peh.UserId
)
SELECT
    ua.DisplayName,
    ua.Reputation,
    ua.CreationDate AS UserCreationDate,
    ua.LastAccessDate,
    ua.TotalPosts,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalScore,
    ua.AvgPostViewCount,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ues.EditedPostsCount,
    ues.TotalEditTimeMinutes,
    ues.AvgEditTimeMinutes,
    ues.TitleEdits,
    ues.BodyEdits,
    ues.TagEdits,
    pm.Title AS SamplePostTitle,
    pm.PostTypeName,
    pm.CreationDate AS PostCreationDate,
    pm.Score AS PostScore,
    pm.ViewCount AS PostViewCount,
    pm.AnswerCount AS PostAnswerCount,
    pm.FavoriteCount AS PostFavoriteCount,
    pm.DaysToClose,
    pm.TotalInteractions,
    pm.DuplicateLinksAsQuestion,
    pm.DuplicateLinksAsAnswer,
    pm.TotalCommentScore,
    pm.OwnerCommentsCount,
    pm.ProtectionStatus,
    pm.ScoreRank,
    pm.ViewRankByPostType,
    CASE WHEN pht.Name IS NOT NULL THEN pht.Name ELSE 'No Specific History Type' END AS LastPostHistoryType,
    COALESCE(u_last_edit.DisplayName, 'Unknown') AS LastEditorDisplayName,
    ph_latest.CreationDate AS LastPostHistoryDate,
    (SELECT Name FROM PostTypes WHERE Id = COALESCE(p.PostTypeId, 1)) AS PostTypeForJoin,
    CASE WHEN p.Score > 100 THEN 'High Score' WHEN p.Score > 0 THEN 'Positive Score' ELSE 'Zero or Negative Score' END AS ScoreCategory,
    UPPER(SUBSTRING(pm.Title FROM 1 FOR 3)) AS TitlePrefix,
    CASE
        WHEN CHAR_LENGTH(pm.Title) > 50 THEN 'Long Title'
        WHEN CHAR_LENGTH(pm.Title) BETWEEN 20 AND 50 THEN 'Medium Title'
        ELSE 'Short Title'
    END AS TitleLengthCategory,
    CASE
        WHEN p.ClosedDate IS NOT NULL AND p.ClosedDate < (cast('2024-10-01' as date) - INTERVAL '365 day') THEN 'Old Closed Post'
        WHEN p.ClosedDate IS NOT NULL THEN 'Recent Closed Post'
        ELSE 'Open Post'
    END AS PostStatus,
    (SELECT COUNT(*) FROM PostHistory ph_sub WHERE ph_sub.PostId = pm.PostId AND ph_sub.PostHistoryTypeId = 10) AS CloseVoteCount,
    (SELECT COUNT(*) FROM PostHistory ph_sub WHERE ph_sub.PostId = pm.PostId AND ph_sub.PostHistoryTypeId = 11) AS ReopenVoteCount,
    LEAST(COALESCE(ua.TotalPosts, 0), COALESCE(pm.Score, 0)) AS MinPostScoreOrPostCount,
    GREATEST(COALESCE(ua.TotalPosts, 0), COALESCE(pm.Score, 0)) AS MaxPostScoreOrPostCount,
    ua.TotalPosts - COALESCE(ues.EditedPostsCount, 0) AS UntouchedPostCount,
    CASE WHEN pm.Title LIKE '%?' THEN 1 ELSE 0 END AS TitleEndsWithQuestionMark,
    CASE WHEN ua.Location IS NULL THEN 'No Location' ELSE 'Has Location' END AS LocationStatus,
    LOWER(COALESCE(ua.WebsiteUrl, 'no-website')) AS NormalizedWebsiteUrl,
    CASE
        WHEN ua.Reputation BETWEEN 1 AND 99 THEN 'New User'
        WHEN ua.Reputation BETWEEN 100 AND 999 THEN 'Established User'
        WHEN ua.Reputation >= 1000 THEN 'Experienced User'
        ELSE 'Uncategorized'
    END AS ReputationLevel,
    CASE
        WHEN CAST(EXTRACT(HOUR FROM ua.CreationDate) AS INTEGER) BETWEEN 8 AND 17 THEN 'Working Hours'
        ELSE 'Off Hours'
    END AS UserCreationHourCategory,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = ua.UserId AND v.VoteTypeId = 2) AS UserUpVotesGiven,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = ua.UserId AND v.VoteTypeId = 3) AS UserDownVotesGiven,
    (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.UserId = ua.UserId AND v.VoteTypeId = 8) AS TotalBountyAmount,
    p.Id AS OriginalPostId,
    COALESCE(p.OwnerUserId, -999) AS CoalescedOwnerUserId,
    CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Wiki' ELSE 'User Owned' END AS OwnershipType,
    (SELECT COUNT(*) FROM Posts p_inner WHERE p_inner.ParentId = p.Id) AS AnswerCountForQuestion
FROM UserActivity ua
LEFT JOIN UserEditStats ues ON ua.UserId = ues.UserId
LEFT JOIN PostMetrics pm ON ua.UserId = pm.OwnerUserId
LEFT JOIN Posts p ON pm.PostId = p.Id
LEFT JOIN PostHistory ph_latest ON p.Id = ph_latest.PostId AND ph_latest.CreationDate = (SELECT MAX(CreationDate) FROM PostHistory ph_sub WHERE ph_sub.PostId = p.Id)
LEFT JOIN PostHistoryTypes pht ON ph_latest.PostHistoryTypeId = pht.Id
LEFT JOIN Users u_last_edit ON ph_latest.UserId = u_last_edit.Id
WHERE ua.TotalPosts > 5
ORDER BY ua.Reputation DESC, pm.Score DESC
LIMIT 100;