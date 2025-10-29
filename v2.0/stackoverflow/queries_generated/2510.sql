-- {"query": "2510.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1703} 
WITH RecursivePostTags AS (
    SELECT 
        p.Id AS PostId,
        p.Tags,
        UNNEST(string_to_array(
            substring(p.Tags from 2 for length(p.Tags)-2),
            '><'
        )) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
UserBadgesCount AS (
    SELECT 
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges 
    GROUP BY UserId
),
PostVotesSummary AS (
    SELECT 
        p.Id AS PostId,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 5) AS FavoriteVotes,
        COALESCE(SUM(v.BountyAmount),0) AS TotalBounty
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.Id
),
LatestPostHistory AS (
    SELECT DISTINCT ON (ph.PostId)
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.UserDisplayName,
        ph.Comment
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10,11,12,13) -- Closed, Reopened, Deleted, Undeleted
    ORDER BY ph.PostId, ph.CreationDate DESC
),
UserActivityRanked AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(ubc.GoldBadges,0) AS GoldBadges,
        COALESCE(ubc.SilverBadges,0) AS SilverBadges,
        COALESCE(ubc.BronzeBadges,0) AS BronzeBadges,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersCount,
        RANK() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS ReputationRank,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC NULLS LAST) AS LocationReputationOrder
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN UserBadgesCount ubc ON ubc.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges
),
DuplicateLinksAndVotes AS (
    SELECT 
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        p1.Title AS PostTitle,
        p2.Title AS RelatedPostTitle,
        p1.Score AS PostScore,
        p2.Score AS RelatedPostScore,
        COALESCE(pv1.UpVotes,0) AS PostUpVotes,
        COALESCE(pv2.UpVotes,0) AS RelatedPostUpVotes,
        (pv1.UpVotes - pv1.DownVotes) AS NetVotes,
        (pv2.UpVotes - pv2.DownVotes) AS RelatedNetVotes
    FROM PostLinks pl
    JOIN Posts p1 ON p1.Id = pl.PostId
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId
    LEFT JOIN PostVotesSummary pv1 ON pv1.PostId = p1.Id
    LEFT JOIN PostVotesSummary pv2 ON pv2.PostId = p2.Id
    WHERE pl.LinkTypeId = 3 -- duplicate links
),
QuestionCommentsAgg AS (
    SELECT 
        c.PostId,
        COUNT(c.Id) AS CommentsCount,
        STRING_AGG(c.Text, ' | ' ORDER BY c.CreationDate DESC) AS RecentCommentsConcat,
        MAX(c.Score) AS MaxCommentScore,
        SUM(CASE WHEN c.UserId IS NULL THEN 1 ELSE 0 END) AS AnonymousComments
    FROM Comments c
    JOIN Posts p ON p.Id = c.PostId AND p.PostTypeId = 1
    GROUP BY c.PostId
),
ComplexPostAnalysis AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        COALESCE(qca.CommentsCount,0) AS QuestionComments,
        qca.RecentCommentsConcat,
        COALESCE(dlv.RelatedPostId, NULL) AS DuplicateOfPostId,
        dlv.RelatedPostTitle,
        dlv.NetVotes AS DuplicatePostNetVotes,
        pvs.UpVotes,
        pvs.DownVotes,
        pvs.FavoriteVotes,
        pvs.TotalBounty,
        -- Calculate weighted popularity score
        (p.Score * 2 + COALESCE(pvs.UpVotes,0) - COALESCE(pvs.DownVotes,0) + p.ViewCount / 100 + p.FavoriteCount * 5 + COALESCE(qca.CommentsCount,0)) AS PopularityScore
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN QuestionCommentsAgg qca ON qca.PostId = p.Id
    LEFT JOIN DuplicateLinksAndVotes dlv ON dlv.PostId = p.Id
    LEFT JOIN PostVotesSummary pvs ON pvs.PostId = p.Id
    WHERE p.PostTypeId = 1 AND p.CreationDate > (CURRENT_DATE - INTERVAL '1 year')
)
SELECT 
    cpa.QuestionId,
    cpa.Title,
    cpa.OwnerName,
    cpa.CreationDate,
    cpa.Score,
    cpa.ViewCount,
    cpa.AnswerCount,
    cpa.FavoriteCount,
    substring(cpa.Tags from 2 for length(cpa.Tags) - 2) AS ParsedTags,
    cpa.QuestionComments,
    CASE 
        WHEN cpa.RecentCommentsConcat IS NULL THEN 'No comments' 
        ELSE left(cpa.RecentCommentsConcat, 200) || '...'
    END AS PreviewComments,
    cpa.DuplicateOfPostId,
    cpa.RelatedPostTitle AS DuplicatePostTitle,
    cpa.DuplicatePostNetVotes,
    cpa.UpVotes,
    cpa.DownVotes,
    cpa.FavoriteVotes,
    cpa.TotalBounty,
    cpa.PopularityScore,
    uar.Reputation AS OwnerReputation,
    uar.GoldBadges,
    uar.SilverBadges,
    uar.BronzeBadges,
    uar.QuestionsCount,
    uar.AnswersCount,
    uar.ReputationRank,
    uar.LocationReputationOrder,
    -- Window function: running average popularity score by creation month
    AVG(cpa.PopularityScore) OVER (PARTITION BY DATE_TRUNC('month', cpa.CreationDate) ORDER BY cpa.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningAvgPopularityByMonth
FROM ComplexPostAnalysis cpa
LEFT JOIN UserActivityRanked uar ON uar.UserId = cpa.OwnerUserId
WHERE cpa.PopularityScore > (
    SELECT AVG(Score)*1.1 FROM Posts WHERE PostTypeId = 1 AND CreationDate > (CURRENT_DATE - INTERVAL '1 year')
)
ORDER BY cpa.PopularityScore DESC NULLS LAST
LIMIT 100;