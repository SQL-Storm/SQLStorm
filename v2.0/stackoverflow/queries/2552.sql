WITH RecursiveUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate AS QuestionCreation,
        a.Id AS AnswerId,
        a.CreationDate AS AnswerCreation,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS RecentQuestionRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE u.Reputation > 1000
),
BadgeCounts AS (
    SELECT
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
PostLinkDuplicates AS (
    SELECT DISTINCT
        pl.PostId,
        pl.RelatedPostId
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
),
UserAnswerStats AS (
    SELECT
        a.OwnerUserId AS UserId,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswersCount
    FROM Posts a
    JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
    WHERE a.PostTypeId = 2
    GROUP BY a.OwnerUserId
),
FilteredPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        U.RankPct,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC) AS PostViewRank,
        COALESCE(vc.UpVotes,0) - COALESCE(vc.DownVotes,0) AS NetVotes
    FROM Posts p
    LEFT JOIN (
        SELECT
            Id AS UserIdForRank,
            NTILE(100) OVER (ORDER BY Reputation DESC) AS RankPct
        FROM Users
    ) U ON U.UserIdForRank = p.OwnerUserId
    LEFT JOIN (
        SELECT
            PostId,
            SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY PostId
    ) vc ON vc.PostId = p.Id
    WHERE p.PostTypeId IN (1, 2)
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
),
ComplexUserStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(b.GoldBadges,0) AS GoldBadges,
        COALESCE(b.SilverBadges,0) AS SilverBadges,
        COALESCE(b.BronzeBadges,0) AS BronzeBadges,
        COALESCE(ans.AnswerCount,0) AS AnswerCount,
        COALESCE(ans.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(ans.AcceptedAnswersCount,0) AS AcceptedAnswers,
        COUNT(DISTINCT ph.PostId) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVotesMade,
        LEAD(u.LastAccessDate) OVER (ORDER BY u.Reputation DESC) AS NextMostReputableUserLastAccess,
        u.Reputation,
        u.LastAccessDate
    FROM Users u
    LEFT JOIN BadgeCounts b ON b.UserId = u.Id
    LEFT JOIN UserAnswerStats ans ON ans.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    WHERE u.Reputation > 500
    GROUP BY u.Id, u.DisplayName, b.GoldBadges, b.SilverBadges, b.BronzeBadges,
             ans.AnswerCount, ans.AvgAnswerScore, ans.AcceptedAnswersCount, u.LastAccessDate, u.Reputation
),
TopQuestionsWithDuplicates AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        ARRAY_AGG(DISTINCT t.TagName) FILTER (WHERE t.TagName IS NOT NULL) AS TagList,
        d.RelatedPostId AS DuplicateOfQuestionId
    FROM Posts p
    LEFT JOIN PostLinkDuplicates d ON d.PostId = p.Id
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><')) AS TagName
    ) t ON TRUE
    WHERE p.PostTypeId = 1
      AND p.Score > 10
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, d.RelatedPostId
    ORDER BY p.ViewCount DESC
    LIMIT 100
)
SELECT 
    cu.UserId,
    cu.DisplayName,
    cu.GoldBadges,
    cu.SilverBadges,
    cu.BronzeBadges,
    cu.AnswerCount,
    ROUND(CAST(cu.AvgAnswerScore AS numeric), 2) AS AverageAnswerScore,
    cu.AcceptedAnswers,
    cu.CloseVotesMade,
    cu.NextMostReputableUserLastAccess,
    tq.QuestionId,
    tq.Title AS QuestionTitle,
    tq.Score AS QuestionScore,
    tq.ViewCount AS QuestionViews,
    tq.AnswerCount AS QuestionAnswerCount,
    array_to_string(tq.TagList, ', ') AS Tags,
    CASE
        WHEN tq.DuplicateOfQuestionId IS NOT NULL THEN 'Duplicate'
        ELSE 'Original'
    END AS QuestionStatus,
    CASE 
        WHEN cu.Reputation / NULLIF(cu.AnswerCount,0) > 100 THEN 'High Impact User'
        WHEN cu.Reputation BETWEEN 500 AND 2000 THEN 'Rising User'
        ELSE 'Regular User'
    END AS UserImpactCategory
FROM ComplexUserStats cu
LEFT JOIN TopQuestionsWithDuplicates tq ON tq.OwnerUserId = cu.UserId
WHERE cu.AnswerCount > 5
ORDER BY cu.GoldBadges DESC, cu.AnswerCount DESC, tq.ViewCount DESC NULLS LAST;