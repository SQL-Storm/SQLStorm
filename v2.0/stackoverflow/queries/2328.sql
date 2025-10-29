-- {"query": "2328.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1666}
WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT 
        t.Id, 
        t.TagName, 
        COALESCE(p.ViewCount, 0) AS ViewCount,
        COALESCE(t.Count, 0) AS TagUsageCount,
        p.CreationDate AS TagCreationDate
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
    WHERE t.TagName IS NOT NULL

  UNION ALL

    SELECT 
        t2.Id, 
        t2.TagName, 
        h.ViewCount + COALESCE(p2.ViewCount,0) AS ViewCount,
        h.TagUsageCount + COALESCE(t2.Count,0) AS TagUsageCount,
        LEAST(h.TagCreationDate, p2.CreationDate) AS TagCreationDate
    FROM Tags t2
    JOIN RecursiveTagHierarchy h ON t2.Id <> h.Id AND t2.Id > h.Id
    LEFT JOIN Posts p2 ON p2.Id = t2.ExcerptPostId
    WHERE t2.TagName IS NOT NULL
),
UserBadgeCounts AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
PostVoteStats AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoriteVotes,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount
),
UserActivity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Location,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COALESCE(bc.GoldBadges,0) AS GoldBadges,
        COALESCE(bc.SilverBadges,0) AS SilverBadges,
        COALESCE(bc.BronzeBadges,0) AS BronzeBadges,
        COALESCE(bc.TotalBadges,0) AS TotalBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN UserBadgeCounts bc ON bc.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, u.CreationDate, u.LastAccessDate, bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges, bc.TotalBadges
),
RecentPopularQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.DisplayName AS OwnerName,
        uv.UpVotes,
        uv.DownVotes,
        uv.FavoriteVotes,
        uv.TotalBounty,
        RANK() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS PopularityRank
    FROM Posts p
    JOIN PostVoteStats uv ON uv.PostId = p.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days')
      AND (p.ClosedDate IS NULL OR p.ClosedDate > CAST('2024-10-01 12:34:56' AS timestamp))
),
ClosedQuestionDetails AS (
    SELECT 
        ph.PostId,
        ph.CreationDate AS CloseDate,
        crt.Name AS CloseReason,
        p.Title,
        u.DisplayName AS OwnerName
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON CAST(crt.Id AS varchar) = ph.Comment
    JOIN Posts p ON p.Id = ph.PostId
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE ph.PostHistoryTypeId = 10 
      AND ph.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
),
AnswerStatsByQuestion AS (
    SELECT 
        pq.Id AS QuestionId,
        COUNT(pa.Id) AS AnswerCount,
        AVG(pa.Score) AS AvgAnswerScore,
        MAX(pa.Score) AS MaxAnswerScore,
        MIN(pa.Score) AS MinAnswerScore,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId END) AS TotalAnswerUpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId END) AS TotalAnswerDownVotes
    FROM Posts pq
    LEFT JOIN Posts pa ON pa.ParentId = pq.Id AND pa.PostTypeId = 2
    LEFT JOIN Votes v ON v.PostId = pa.Id
    WHERE pq.PostTypeId = 1
    GROUP BY pq.Id
),
CorrelatedLatestComment AS (
    SELECT
        c.PostId,
        c.Text AS LatestCommentText,
        c.CreationDate AS LatestCommentDate,
        COALESCE(u.DisplayName, c.UserDisplayName) AS Commenter
    FROM (
        SELECT c_inner.*, 
               ROW_NUMBER() OVER (PARTITION BY c_inner.PostId ORDER BY c_inner.CreationDate DESC) AS rn
        FROM Comments c_inner
    ) c
    LEFT JOIN Users u ON u.Id = c.UserId
    WHERE c.rn = 1
)
SELECT 
    uq.Id AS UserId,
    uq.DisplayName,
    uq.Reputation,
    uq.Location,
    uq.TotalPosts,
    uq.TotalComments,
    uq.GoldBadges, uq.SilverBadges, uq.BronzeBadges,
    'Rank ' || uq.ReputationRank AS ReputationRankLabel,
    rpq.Id AS RecentQuestionId,
    rpq.Title AS RecentQuestionTitle,
    rpq.CreationDate AS RecentQuestionDate,
    rpq.Score AS RecentQuestionScore,
    rpq.ViewCount AS RecentQuestionViews,
    rpq.Tags AS RecentQuestionTags,
    rpq.OwnerName AS QuestionOwner,
    'Up:' || COALESCE(rpq.UpVotes,0) || ' Down:' || COALESCE(rpq.DownVotes,0) || ' Favs:' || COALESCE(rpq.FavoriteVotes,0) || ' Bounty:' || COALESCE(rpq.TotalBounty,0) AS VoteSummary,
    ad.AnswerCount,
    ROUND(COALESCE(ad.AvgAnswerScore,0),2) AS AvgAnswerScore,
    ad.MaxAnswerScore,
    ad.MinAnswerScore,
    ad.TotalAnswerUpVotes,
    ad.TotalAnswerDownVotes,
    COALESCE(cd.CloseReason, 'Open') AS QuestionStatus,
    cd.CloseDate,
    cd.OwnerName AS ClosedBy,
    clc.LatestCommentText,
    clc.LatestCommentDate,
    clc.Commenter
FROM UserActivity uq
LEFT JOIN RecentPopularQuestions rpq ON rpq.OwnerName = uq.DisplayName
LEFT JOIN AnswerStatsByQuestion ad ON ad.QuestionId = rpq.Id
LEFT JOIN ClosedQuestionDetails cd ON cd.PostId = rpq.Id
LEFT JOIN CorrelatedLatestComment clc ON clc.PostId = rpq.Id
WHERE uq.TotalPosts > 10
  AND uq.Reputation > 1000
  AND rpq.Score > 5
ORDER BY uq.ReputationRank ASC, rpq.Score DESC
LIMIT 100;