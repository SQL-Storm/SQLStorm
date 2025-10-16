-- {"query": "471.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1892} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.TagName] AS TagPath
    FROM Tags t
    WHERE t.IsModeratorOnly = 0

    UNION ALL

    SELECT
        t.Id,
        t.TagName,
        t.Count,
        r.TagPath || t.TagName
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON t.Id <> r.Id AND t.Count < r.Count
    WHERE array_length(r.TagPath,1) < 3
),
UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END), 0) AS TagBasedBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS UserRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostActivityWindow AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        p.Title,
        LEAD(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostDate,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS ScoreRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS PostsByUser
    FROM Posts p
    WHERE p.PostTypeId IN (1,2) -- Questions and Answers only
),
PostCloseInfo AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS ClosedAt,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate ELSE NULL END) AS ReopenedAt,
        MAX(CAST(ph.Comment AS INT)) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseReasonId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10,11)
    GROUP BY ph.PostId
),
TopPostsWithComments AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        COUNT(c.Id) AS CommentCount,
        STRING_AGG(DISTINCT COALESCE(u.DisplayName, c.UserDisplayName), ', ' ORDER BY c.CreationDate DESC) AS RecentCommenters
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Users u ON u.Id = c.UserId
    WHERE p.PostTypeId = 1 -- questions only
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags
    HAVING COUNT(c.Id) > 5
),
AnswerStats AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(CASE WHEN a.OwnerUserId IS NULL THEN 1 ELSE 0 END) AS AnonymousAnswerCount
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
UserActivitySummary AS (
    SELECT
        u.Id,
        u.DisplayName,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionsPosted,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswersPosted,
        COALESCE(SUM(vt.VoteTypeId = 2)::INT, 0) AS UpVotesReceived,
        COALESCE(SUM(vt.VoteTypeId = 3)::INT, 0) AS DownVotesReceived,
        MAX(p.Score) AS MaxPostScore,
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(DISTINCT ph.PostId) FILTER (WHERE ph.PostHistoryTypeId = 10) AS TimesPostsClosed
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes vt ON vt.PostId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
    GROUP BY u.Id, u.DisplayName
),
DuplicateLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        p1.Title AS PostTitle,
        p2.Title AS RelatedPostTitle,
        lt.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN Posts p1 ON p1.Id = pl.PostId
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE pl.LinkTypeId = 3 -- Duplicate
),
ComplexUserPostAnalysis AS (
    SELECT
        uas.Id AS UserId,
        uas.DisplayName,
        uas.QuestionsPosted,
        uas.AnswersPosted,
        uas.UpVotesReceived,
        uas.DownVotesReceived,
        uas.MaxPostScore,
        uas.FirstPostDate,
        uas.LastPostDate,
        uas.TimesPostsClosed,
        COALESCE(ab.GoldBadges,0) AS GoldBadges,
        COALESCE(ab.SilverBadges,0) AS SilverBadges,
        COALESCE(ab.BronzeBadges,0) AS BronzeBadges,
        COALESCE(ab.TagBasedBadges,0) AS TagBasedBadges,
        CASE
            WHEN uas.TimesPostsClosed > 5 THEN 'High closure rate'
            WHEN uas.UpVotesReceived > uas.DownVotesReceived THEN 'Positive reception'
            ELSE 'Mixed reception'
        END AS UserReputationCategory
    FROM UserActivitySummary uas
    LEFT JOIN UserBadgeStats ab ON ab.UserId = uas.Id
)
SELECT
    cupa.UserId,
    cupa.DisplayName,
    cupa.QuestionsPosted,
    cupa.AnswersPosted,
    cupa.UpVotesReceived,
    cupa.DownVotesReceived,
    cupa.GoldBadges,
    cupa.SilverBadges,
    cupa.BronzeBadges,
    cupa.TagBasedBadges,
    cupa.UserReputationCategory,
    COALESCE(ans.AnswerCount, 0) AS TotalAnswersToUserQuestions,
    COALESCE(ans.AvgAnswerScore, 0) AS AvgScoreOfAnswersToUserQuestions,
    COALESCE(ans.MaxAnswerScore, 0) AS MaxScoreOfAnswersToUserQuestions,
    COALESCE(ans.AnonymousAnswerCount, 0) AS AnonymousAnswersToUserQuestions,
    STRING_AGG(DISTINCT dt.TagName, ', ') AS PopularTagsUsed,
    STRING_AGG(DISTINCT dl.PostTitle || ' -> ' || dl.RelatedPostTitle, '; ') AS DuplicatePostLinks
FROM ComplexUserPostAnalysis cupa
LEFT JOIN Posts q ON q.OwnerUserId = cupa.UserId AND q.PostTypeId = 1
LEFT JOIN AnswerStats ans ON ans.QuestionId = q.Id
LEFT JOIN RecursiveTagHierarchy dt ON dt.TagName = ANY(string_to_array(substring(q.Tags FROM 2 FOR char_length(q.Tags)-2), '><'))
LEFT JOIN DuplicateLinks dl ON dl.PostId = q.Id
WHERE cupa.QuestionsPosted > 10
GROUP BY
    cupa.UserId,
    cupa.DisplayName,
    cupa.QuestionsPosted,
    cupa.AnswersPosted,
    cupa.UpVotesReceived,
    cupa.DownVotesReceived,
    cupa.GoldBadges,
    cupa.SilverBadges,
    cupa.BronzeBadges,
    cupa.TagBasedBadges,
    cupa.UserReputationCategory,
    ans.AnswerCount,
    ans.AvgAnswerScore,
    ans.MaxAnswerScore,
    ans.AnonymousAnswerCount
ORDER BY cupa.UpVotesReceived DESC, cupa.GoldBadges DESC, cupa.QuestionsPosted DESC
LIMIT 50;
