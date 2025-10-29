-- {"query": "1464.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1633} 

WITH UserPostStats AS (
    SELECT
        OwnerUserId AS UserId,
        COUNT(Id) AS TotalPosts,
        COUNT(CASE WHEN PostTypeId = 1 THEN Id END) AS TotalQuestions,
        COUNT(CASE WHEN PostTypeId = 2 THEN Id END) AS TotalAnswers,
        SUM(COALESCE(Score, 0)) AS TotalPostScore,
        AVG(COALESCE(Score, 0)) AS AvgPostScore,
        MIN(CreationDate) AS FirstPostDate,
        MAX(CreationDate) AS LastPostDate,
        SUM(COALESCE(ViewCount, 0)) AS TotalPostViewCount,
        SUM(COALESCE(FavoriteCount, 0)) AS TotalPostFavoriteCount,
        SUM(COALESCE(AnswerCount, 0)) AS TotalAnswerCountForQuestions,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersGivenByOwner
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
UserCommentStats AS (
    SELECT
        UserId,
        COUNT(Id) AS TotalCommentsMade,
        SUM(COALESCE(Score, 0)) AS TotalCommentScore
    FROM Comments
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
UserVoteGivenStats AS (
    SELECT
        UserId,
        SUM(CASE WHEN VoteTypeId IN (2, 5) THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN VoteTypeId IN (3, 4, 10, 12) THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        COUNT(DISTINCT PostId) AS PostsVotedOn
    FROM Votes
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
UserVoteReceivedStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS ReceivedUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS ReceivedDownVotes
    FROM Posts p
    INNER JOIN Votes v ON p.Id = v.PostId
    WHERE p.OwnerUserId IS NOT NULL AND v.VoteTypeId IN (2, 3)
    GROUP BY p.OwnerUserId
),
UserBadgeStats AS (
    SELECT
        UserId,
        COUNT(Id) AS TotalBadges,
        COUNT(CASE WHEN Class = 1 THEN Id END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN Id END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN Id END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate AS UserLastAccessDate,
        COALESCE(ups.TotalPosts, 0) AS TotalPosts,
        COALESCE(ups.TotalQuestions, 0) AS TotalQuestions,
        COALESCE(ups.TotalAnswers, 0) AS TotalAnswers,
        COALESCE(ups.TotalPostScore, 0) AS TotalPostScore,
        COALESCE(ups.AvgPostScore, 0) AS AvgPostScore,
        COALESCE(ucs.TotalCommentsMade, 0) AS TotalCommentsMade,
        COALESCE(uvgs.TotalUpVotesGiven, 0) AS TotalUpVotesGiven,
        COALESCE(uvgs.TotalDownVotesGiven, 0) AS TotalDownVotesGiven,
        COALESCE(uvrs.ReceivedUpVotes, 0) AS ReceivedUpVotes,
        COALESCE(uvrs.ReceivedDownVotes, 0) AS ReceivedDownVotes,
        COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
        COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
        ups.FirstPostDate,
        ups.LastPostDate,
        COALESCE(ups.TotalPostViewCount, 0) AS TotalPostViewCount,
        COALESCE(ups.TotalPostFavoriteCount, 0) AS TotalPostFavoriteCount,
        COALESCE(ups.TotalAnswerCountForQuestions, 0) AS TotalAnswerCountForQuestions,
        COALESCE(ups.TotalAnswersGivenByOwner, 0) AS TotalAnswersGivenByOwner
    FROM Users u
    LEFT JOIN UserPostStats ups ON u.Id = ups.UserId
    LEFT JOIN UserCommentStats ucs ON u.Id = ucs.UserId
    LEFT JOIN UserVoteGivenStats uvgs ON u.Id = uvgs.UserId
    LEFT JOIN UserVoteReceivedStats uvrs ON u.Id = uvrs.UserId
    LEFT JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
),
PostHistoryAgg AS (
    SELECT
        PostId,
        COUNT(DISTINCT CASE WHEN PostHistoryTypeId IN (4, 5, 6) THEN Id END) AS EditHistoryCount,
        MAX(CASE WHEN PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosedFlag,
        MAX(CASE WHEN PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopenedFlag,
        COUNT(DISTINCT CASE WHEN UserId IS NOT NULL AND PostHistoryTypeId IN (4, 5, 6) THEN UserId END) AS UniqueEditorCount,
        MAX(CASE WHEN PostHistoryTypeId = 1 THEN Text END) AS InitialHistoryTitle
    FROM PostHistory
    GROUP BY PostId
),
PostLinkAgg AS (
    SELECT PostId, MAX(1) AS HasDuplicateLink
    FROM PostLinks
    WHERE LinkTypeId = 3
    GROUP BY PostId
),
PostQualityExtended AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        p.ParentId,
        p.LastEditDate,
        p.LastActivityDate,
        p.ClosedDate,
        p.CommunityOwnedDate,
        p.Title,
        p.Tags,
        LENGTH(p.Body) AS BodyLength,
        COALESCE(pha.EditHistoryCount, 0) AS EditHistoryCount,
        COALESCE(pha.WasClosedFlag, 0) AS WasClosedFlag,
        COALESCE(pha.WasReopenedFlag, 0) AS WasReopenedFlag,
        COALESCE(pla.HasDuplicateLink, 0) AS HasDuplicateLink,
        COALESCE(pha.UniqueEditorCount, 0) AS UniqueEditorCount,
        (SELECT MAX(p2.Score)