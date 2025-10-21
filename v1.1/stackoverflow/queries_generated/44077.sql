-- {"query": "44077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1603}
Here is an elaborate SQL query for performance benchmarking:

WITH cte AS (
    SELECT 
        p.Id, 
        p.PostTypeId, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount, 
        p.CommentCount, 
        p.FavoriteCount, 
        p.ClosedDate, 
        p.CommunityOwnedDate, 
        u.Reputation, 
        u.CreationDate AS UserCreationDate, 
        u.LastAccessDate, 
        u.Views AS UserViews, 
        u.UpVotes, 
        u.DownVotes, 
        b.Id AS BadgeId, 
        b.Name AS BadgeName, 
        b.Date AS BadgeDate, 
        b.Class AS BadgeClass, 
        b.TagBased AS BadgeTagBased, 
        v.Id AS VoteId, 
        v.VoteTypeId, 
        v.CreationDate AS VoteCreationDate, 
        v.BountyAmount, 
        c.Id AS CommentId, 
        c.Score AS CommentScore, 
        c.CreationDate AS CommentCreationDate, 
        l.Id AS LinkId, 
        l.LinkTypeId, 
        l.CreationDate AS LinkCreationDate, 
        ph.Id AS PostHistoryId, 
        ph.PostHistoryTypeId, 
        ph.CreationDate AS PostHistoryCreationDate, 
        ph.Comment AS PostHistoryComment, 
        ph.Text AS PostHistoryText
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostLinks l ON p.Id = l.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1 
        AND p.CreationDate BETWEEN '2022-01-01' AND '2022-12-31'
        AND p.OwnerUserId IS NOT NULL
        AND p.OwnerUserId <> -1
)
SELECT 
    COUNT(*) AS TotalQuestions,
    SUM(CASE WHEN ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedQuestions,
    SUM(CASE WHEN CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END) AS CommunityOwnedQuestions,
    AVG(Score) AS AvgQuestionScore,
    AVG(ViewCount) AS AvgQuestionViews,
    AVG(AnswerCount) AS AvgQuestionAnswers,
    AVG(CommentCount) AS AvgQuestionComments,
    AVG(FavoriteCount) AS AvgQuestionFavorites,
    AVG(Reputation) AS AvgUserReputation,
    AVG(UserViews) AS AvgUserViews,
    AVG(UpVotes) AS AvgUserUpvotes,
    AVG(DownVotes) AS AvgUserDownvotes,
    COUNT(DISTINCT BadgeId) AS TotalBadges,
    SUM(CASE WHEN BadgeClass = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN BadgeClass = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN BadgeClass = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    COUNT(DISTINCT VoteId) AS TotalVotes,
    SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
    SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes,
    SUM(CASE WHEN VoteTypeId = 8 THEN 1 ELSE 0 END) AS TotalBountyStarts,
    SUM(CASE WHEN VoteTypeId = 9 THEN 1 ELSE 0 END) AS TotalBountyClosed,
    COUNT(DISTINCT CommentId) AS TotalComments,
    AVG(CommentScore) AS AvgCommentScore,
    COUNT(DISTINCT LinkId) AS TotalLinks,
    SUM(CASE WHEN LinkTypeId = 1 THEN 1 ELSE 0 END) AS TotalLinkedPosts,
    SUM(CASE WHEN LinkTypeId = 3 THEN 1 ELSE 0 END) AS TotalDuplicatePosts,
    COUNT(DISTINCT PostHistoryId) AS TotalPostHistory,
    SUM(CASE WHEN PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalPostClosed,
    SUM(CASE WHEN PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TotalPostReopened,
    SUM(CASE WHEN PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS TotalPostDeleted,
    SUM(CASE WHEN PostHistoryTypeId = 13 THEN 1 ELSE 0 END) AS TotalPostUndeleted,
    SUM(CASE WHEN PostHistoryTypeId = 14 THEN 1 ELSE 0 END) AS TotalPostLocked,
    SUM(CASE WHEN PostHistoryTypeId = 15 THEN 1 ELSE 0 END) AS TotalPostUnlocked,
    SUM(CASE WHEN PostHistoryTypeId = 16 THEN 1 ELSE 0 END) AS TotalCommunityOwned,
    SUM(CASE WHEN PostHistoryTypeId = 19 THEN 1 ELSE 0 END) AS TotalPostProtected,
    SUM(CASE WHEN PostHistoryTypeId = 20 THEN 1 ELSE 0 END) AS TotalPostUnprotected
FROM cte;
